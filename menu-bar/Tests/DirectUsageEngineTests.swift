import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
}

/// Fail closed if a regression tries to fetch one of these synthetic credentials.
private final class NoNetworkProtocol: URLProtocol {
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@main
struct DirectUsageEngineTests {
    static func main() async {
        do {
            try await runChecks()
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    private static func runChecks() async throws {
        _ = URLProtocol.registerClass(NoNetworkProtocol.self)
        try FileManager.default.createDirectory(at: UsageStateStore.supportDirectory, withIntermediateDirectories: true)
        let root = UsageStateStore.supportDirectory.resolvingSymlinksInPath()

        try testExpiredCCSwitchAccountIsDiscovered(root)
        try testNewestCredentialWinsAcrossSources(root)
        try testDifferentUsersInSameWorkspaceRemainSeparate(root)
        try testExcludedAccountsAreRemovedBeforeFetching(root)
        try testManagedHomesAreDiscoveredFirst(root)
        try await testExpiredAccountPreservesLastSuccessfulUsage(root)
        try await testFirstSeenExpiredAccountNeedsSignIn(root)
        try check(NoNetworkProtocol.requestCount == 0, "Expired credentials must not cause API requests")
        print("PASS: 7 DirectUsageEngine fixture checks; no network requests")
    }

    // Regression: an expired CC Switch account must remain visible to the user.
    private static func testExpiredCCSwitchAccountIsDiscovered(_ root: URL) throws {
        let db = root.appendingPathComponent("expired.db")
        try writeDatabase(db, auths: [auth(user: "second-user", expiry: past)])
        let accounts = DirectUsageEngine.ccSwitchAccounts(database: db)
        try check(accounts.count == 1, "Expired CC Switch account disappeared during discovery")
        try check(accounts.first?.id == "codex:second-user", "Discovery lost the expired user's identity")
    }

    // Regression: a stale CLI copy must not suppress a newer CC Switch credential.
    private static func testNewestCredentialWinsAcrossSources(_ root: URL) throws {
        let cli = root.appendingPathComponent("old-cli")
        try writeAuth(auth(user: "same-user", expiry: past), home: cli)
        let db = root.appendingPathComponent("newer.db")
        try writeDatabase(db, auths: [auth(user: "same-user", expiry: future)])
        let candidates = DirectUsageEngine.codexCLIAccounts(homes: [cli])
            + DirectUsageEngine.ccSwitchAccounts(database: db)
        let selected = DirectUsageEngine.selectAccounts(candidates)
        try check(selected.count == 1, "Duplicate credentials produced duplicate account cards")
        try check(selected.first?.source == "cc-switch", "An older CLI token hid a fresh CC Switch token")
        try check(selected.first?.expiresAt == future * 1000, "Selected credential is not the newest")

        let reversed = DirectUsageEngine.selectAccounts(Array(candidates.reversed()))
        try check(reversed.first?.expiresAt == future * 1000, "Credential selection depends on input order")
    }

    // Regression: team/workspace identity must not merge two individual users.
    private static func testDifferentUsersInSameWorkspaceRemainSeparate(_ root: URL) throws {
        let db = root.appendingPathComponent("two-users.db")
        try writeDatabase(db, auths: [auth(user: "user-a", expiry: future), auth(user: "user-b", expiry: future)])
        let accounts = DirectUsageEngine.selectAccounts(DirectUsageEngine.ccSwitchAccounts(database: db))
        try check(Set(accounts.map(\.id)) == ["codex:user-a", "codex:user-b"], "Separate users sharing a workspace were merged")
    }

    // Regression: removal must exclude every discovered credential for that user.
    private static func testExcludedAccountsAreRemovedBeforeFetching(_ root: URL) throws {
        let db = root.appendingPathComponent("excluded.db")
        try writeDatabase(db, auths: [auth(user: "removed", expiry: past), auth(user: "kept", expiry: past)])
        let accounts = DirectUsageEngine.selectAccounts(
            DirectUsageEngine.ccSwitchAccounts(database: db), excludedAccountIDs: ["codex:removed"]
        )
        try check(accounts.map(\.id) == ["codex:kept"], "A removed account survived discovery filtering")
    }

    // Regression: a verified managed login must be found, with tie preference over CLI copies.
    private static func testManagedHomesAreDiscoveredFirst(_ root: URL) throws {
        let home = root.appendingPathComponent("fake-home")
        let support = root.appendingPathComponent("managed-support")
        let managed = support.appendingPathComponent("Accounts/Y29kZXg6bWFuYWdlZA")
        let cli = home.appendingPathComponent(".codex")
        let extra = home.appendingPathComponent(".codex-another")
        try writeAuth(auth(user: "managed", expiry: future), home: managed)
        try writeAuth(auth(user: "managed", expiry: future), home: cli)
        try writeAuth(auth(user: "other", expiry: future), home: extra)
        let homes = DirectUsageEngine.codexHomes(home: home, supportDirectory: support)
        try check(homes.first?.resolvingSymlinksInPath().path == managed.resolvingSymlinksInPath().path,
                  "Managed credential home is not discovered first")
        try check(homes.contains { $0.resolvingSymlinksInPath().path == extra.resolvingSymlinksInPath().path },
                  "Additional Codex homes stopped being discovered")
        // A developer's CODEX_HOME may be set; only open credentials created in this fixture root.
        let fixtureHomes = homes.filter { $0.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") }
        let accounts = DirectUsageEngine.selectAccounts(DirectUsageEngine.codexCLIAccounts(homes: fixtureHomes))
        try check(accounts.count == 2, "Managed/CLI credentials are not deduplicated by user")
    }

    // Regression: preserving stale percentages must preserve their successful fetch timestamp too.
    private static func testExpiredAccountPreservesLastSuccessfulUsage(_ root: URL) async throws {
        let home = root.appendingPathComponent("expired-with-cache")
        try writeAuth(auth(user: "cached", expiry: past), home: home)
        let account = DirectUsageEngine.codexCLIAccounts(homes: [home])[0]
        let previous = UsageAccount(
            id: "codex:cached", provider: "codex", label: "cached@example.invalid", plan: "team", source: "cli",
            status: "ok", statusDetail: nil, statusHint: nil,
            windows: [UsageWindow(key: "5h", label: "5-hour", usedPercent: 75, remainingPercent: 25,
                                  windowSeconds: 18000, resetsAt: "2026-11-01T12:00:00Z", exhausted: false)],
            extras: nil, updatedAt: "2026-11-01T08:00:00Z", limitReached: false
        )
        let result = await DirectUsageEngine.fetchAccount(account, previousAccount: previous)
        try check(result.status == "auth", "Expired credentials did not produce a sign-in state")
        try check(result.windows.first?.remainingPercent == 25, "Last known usage was discarded")
        try check(result.updatedAt == "2026-11-01T08:00:00Z", "Cached usage was incorrectly stamped as fresh")
        try check(result.statusHint != nil, "Expired account has no sign-in guidance")
    }

    private static func testFirstSeenExpiredAccountNeedsSignIn(_ root: URL) async throws {
        let home = root.appendingPathComponent("expired-no-cache")
        try writeAuth(auth(user: "uncached", expiry: past), home: home)
        let account = DirectUsageEngine.codexCLIAccounts(homes: [home])[0]
        let result = await DirectUsageEngine.fetchAccount(account, previousAccount: nil)
        try check(result.status == "auth", "First-seen expired account must be visible as needing sign-in")
        try check(result.windows.isEmpty, "First-seen expired account invented usage values")
    }

    private static let past: Double = 1_600_000_000
    private static let future: Double = 4_000_000_000

    private static func auth(user: String, expiry: Double) -> [String: Any] {
        let claims: [String: Any] = [
            "exp": expiry,
            "https://api.openai.com/profile": ["email": "\(user)@example.invalid"],
            "https://api.openai.com/auth": ["chatgpt_user_id": user, "chatgpt_account_id": "same-workspace", "chatgpt_plan_type": "team"],
        ]
        let payload = try! JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return ["auth_mode": "chatgpt", "tokens": ["access_token": "e30.\(payload).fixture-signature", "account_id": "same-workspace"]]
    }

    private static func writeAuth(_ auth: [String: Any], home: URL) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: auth).write(to: home.appendingPathComponent("auth.json"))
    }

    private static func writeDatabase(_ url: URL, auths: [[String: Any]]) throws {
        var sql = "CREATE TABLE providers (name TEXT, app_type TEXT, settings_config TEXT);\n"
        for (index, auth) in auths.enumerated() {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: ["auth": auth]), as: UTF8.self)
                .replacingOccurrences(of: "'", with: "''")
            sql += "INSERT INTO providers VALUES ('Fixture \(index)', 'codex', '\(json)');\n"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, sql]
        try process.run()
        process.waitUntilExit()
        try check(process.terminationStatus == 0, "Could not create fixture database")
    }
}
