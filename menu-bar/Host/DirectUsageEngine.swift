import Foundation

/// A locally discovered provider login. Kept in memory only.
struct DirectAccount: Sendable {
    let id: String
    let provider: String
    let label: String
    let email: String?
    let plan: String?
    let source: String
    let token: String
    let accountId: String?
    let keychain: Bool
    let refreshToken: String?
    let expiresAt: Double?
}

struct DirectResult: Sendable {
    let snapshot: UsageSnapshot
    let error: String?
}

struct DirectError: Error, Sendable {
    let kind: String
    let message: String
}

/// Standalone Codex/Claude/Grok usage collector used by the menu-bar app when
/// DeepSeek Harness is not installed. It reads the same local credential stores
/// as the CLIs, calls the providers' usage endpoints, and writes a non-secret
/// snapshot for the UI and widget.
enum DirectUsageEngine {
    private static let codexURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let claudeURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let claudeTokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let grokURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    private static let claudeKeychainService = "Claude Code-credentials"
    private static let claudeClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let requestTimeout: TimeInterval = 12
    private static let refreshSkewMs: Double = 2 * 60 * 1000

    // MARK: - Collection

    static func collect(previous: UsageSnapshot?) async -> DirectResult {
        let accounts = discoverAccounts()
        let now = Date()

        guard !accounts.isEmpty else {
            let snapshot = UsageSnapshot(version: 1, updatedAt: iso(now), accounts: [])
            try? UsageStateStore.save(snapshot)
            return DirectResult(
                snapshot: snapshot,
                error: "No local accounts found. Sign in with codex login, claude /login, or grok login."
            )
        }

        let previousById = Dictionary(uniqueKeysWithValues: (previous?.accounts ?? []).map { ($0.id, $0) })
        var results: [UsageAccount] = []
        await withTaskGroup(of: UsageAccount.self) { group in
            for account in accounts {
                let previousAccount = previousById[account.id]
                group.addTask {
                    await fetchAccount(account, previousAccount: previousAccount)
                }
            }
            for await account in group {
                results.append(account)
            }
        }

        results.sort { left, right in
            let leftRank = providerRank(left.provider)
            let rightRank = providerRank(right.provider)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
        }

        let snapshot = UsageSnapshot(version: 1, updatedAt: iso(now), accounts: results)
        try? UsageStateStore.save(snapshot)

        let failed = results.filter { $0.status != "ok" }
        let succeeded = results.contains { $0.status == "ok" }
        let error: String?
        if succeeded {
            error = nil
        } else if let first = failed.first {
            error = "Could not refresh usage: \(first.statusDetail ?? first.status)"
        } else {
            error = nil
        }
        return DirectResult(snapshot: snapshot, error: error)
    }

    private static func providerRank(_ provider: String) -> Int {
        switch provider {
        case "codex": return 0
        case "claude": return 1
        case "grok": return 2
        default: return 9
        }
    }

    // MARK: - Discovery

    private static func discoverAccounts() -> [DirectAccount] {
        var accounts: [DirectAccount] = []
        accounts += codexCLIAccounts()
        accounts += ccSwitchAccounts()
        accounts += claudeAccounts()
        accounts += grokAccounts()

        var seen = Set<String>()
        return accounts.filter { account in
            guard !account.token.isEmpty else { return false }
            return seen.insert(account.id).inserted
        }
    }

    private static func codexCLIAccounts() -> [DirectAccount] {
        var accounts: [DirectAccount] = []
        for home in codexHomes() {
            guard let auth = readJSON(home.appendingPathComponent("auth.json")) as? [String: Any],
                  (auth["auth_mode"] as? String) == "chatgpt",
                  let tokens = auth["tokens"] as? [String: Any],
                  let token = tokens["access_token"] as? String else {
                continue
            }
            let fallbackId = tokens["account_id"] as? String
            let info = codexIdentity(token, fallbackAccountId: fallbackId)
            let identity = info.userId ?? info.email ?? info.teamId
            guard let identity, !identity.isEmpty else { continue }
            let label: String
            if let email = info.email {
                label = email
            } else if home.lastPathComponent == ".codex" {
                label = "Codex CLI"
            } else {
                label = "Codex (\(home.lastPathComponent))"
            }
            accounts.append(DirectAccount(
                id: "codex:\(identity)",
                provider: "codex",
                label: label,
                email: info.email,
                plan: info.plan,
                source: "cli",
                token: token,
                accountId: info.teamId,
                keychain: false,
                refreshToken: nil,
                expiresAt: info.expiresAt.map { $0 * 1000 }
            ))
        }
        return accounts
    }

    private static func codexHomes() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var homes: [URL] = []
        if let value = ProcessInfo.processInfo.environment["CODEX_HOME"], !value.isEmpty {
            homes.append(URL(fileURLWithPath: (value as NSString).expandingTildeInPath))
        } else {
            homes.append(home.appendingPathComponent(".codex"))
        }
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: home.path) {
            for entry in entries where entry.hasPrefix(".codex-") && entry != ".codex-auth" {
                let candidate = home.appendingPathComponent(entry)
                if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("auth.json").path) {
                    homes.append(candidate)
                }
            }
        }
        var seen = Set<String>()
        return homes.filter { seen.insert($0.path).inserted }
    }

    private static func ccSwitchAccounts() -> [DirectAccount] {
        let db = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-switch/cc-switch.db")
        guard FileManager.default.fileExists(atPath: db.path) else { return [] }
        guard let output = try? run("/usr/bin/sqlite3", [
            "-readonly", "-json", db.path,
            "SELECT name, settings_config FROM providers WHERE app_type = 'codex'"
        ]), let data = output.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var accounts: [DirectAccount] = []
        let now = Date().timeIntervalSince1970 * 1000
        for row in rows {
            guard let settings = dictionary(from: row["settings_config"]) else { continue }
            guard let auth = dictionary(from: settings["auth"]),
                  let tokens = auth["tokens"] as? [String: Any],
                  let token = tokens["access_token"] as? String else {
                continue
            }
            let info = codexIdentity(token, fallbackAccountId: tokens["account_id"] as? String)
            if let exp = info.expiresAt, exp * 1000 < now + 60_000 { continue }
            let identity = info.userId ?? info.email ?? info.teamId
            guard let identity, !identity.isEmpty else { continue }
            let name = row["name"] as? String
            accounts.append(DirectAccount(
                id: "codex:\(identity)",
                provider: "codex",
                label: info.email ?? name ?? "Codex account",
                email: info.email,
                plan: info.plan,
                source: "cc-switch",
                token: token,
                accountId: info.teamId,
                keychain: false,
                refreshToken: nil,
                expiresAt: info.expiresAt.map { $0 * 1000 }
            ))
        }
        return accounts
    }

    private static func claudeAccounts() -> [DirectAccount] {
        var accounts: [DirectAccount] = []
        if let full = readClaudeKeychainFull(),
           let oauth = full["claudeAiOauth"] as? [String: Any],
           let account = claudeAccount(oauth, keychain: true) {
            accounts.append(account)
        }

        let credentials = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let full = readJSON(credentials) as? [String: Any],
           let oauth = full["claudeAiOauth"] as? [String: Any],
           let account = claudeAccount(oauth, keychain: false) {
            accounts.append(account)
        }

        if let token = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"], !token.isEmpty {
            accounts.append(DirectAccount(
                id: "claude:env",
                provider: "claude",
                label: "Claude Code (env)",
                email: nil,
                plan: nil,
                source: "cli",
                token: token,
                accountId: nil,
                keychain: false,
                refreshToken: nil,
                expiresAt: nil
            ))
        }
        return accounts
    }

    private static func claudeAccount(_ oauth: [String: Any], keychain: Bool) -> DirectAccount? {
        guard let token = (oauth["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }
        let email = (oauth["accountEmail"] as? String)
            ?? (oauth["emailAddress"] as? String)
            ?? (oauth["email"] as? String)
        let identity = email ?? "code"
        return DirectAccount(
            id: "claude:\(identity)",
            provider: "claude",
            label: email ?? "Claude Code",
            email: email,
            plan: oauth["subscriptionType"] as? String,
            source: "cli",
            token: token,
            accountId: nil,
            keychain: keychain,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: number(oauth["expiresAt"])
        )
    }

    private static func grokAccounts() -> [DirectAccount] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory: URL
        if let value = ProcessInfo.processInfo.environment["GROK_HOME"], !value.isEmpty {
            directory = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        } else {
            directory = home.appendingPathComponent(".grok")
        }
        guard let auth = readJSON(directory.appendingPathComponent("auth.json")) as? [String: Any] else {
            return []
        }

        var accounts: [DirectAccount] = []
        for (entryKey, value) in auth {
            guard let entry = value as? [String: Any],
                  let token = (entry["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !token.isEmpty else {
                continue
            }
            let identity = (entry["principal_id"] as? String)
                ?? (entry["user_id"] as? String)
                ?? (entry["email"] as? String)
                ?? entryKey
            let id = "grok:\(identity)"
            if accounts.contains(where: { $0.id == id }) { continue }
            accounts.append(DirectAccount(
                id: id,
                provider: "grok",
                label: (entry["email"] as? String) ?? (entry["first_name"] as? String) ?? "Grok CLI",
                email: entry["email"] as? String,
                plan: (entry["principal_type"] as? String) == "Team" ? "Team" : nil,
                source: "cli",
                token: token,
                accountId: nil,
                keychain: false,
                refreshToken: nil,
                expiresAt: nil
            ))
        }
        return accounts
    }

    // MARK: - Fetch

    private static func fetchAccount(_ account: DirectAccount, previousAccount: UsageAccount?) async -> UsageAccount {
        var current = account
        if current.provider == "claude" {
        }
        do {
            if current.provider == "claude", current.keychain, needsClaudeRefresh(current) {
                current = try await ensureClaudeToken(current)
            }
            do {
                return try await fetch(current)
            } catch let error as DirectError where error.kind == "auth"
                && current.provider == "claude" && current.keychain {
                current = try await ensureClaudeToken(current, force: true)
                return try await fetch(current)
            }
        } catch let error as DirectError {
            return failedAccount(current, error: error, previous: previousAccount)
        } catch {
            return failedAccount(
                current,
                error: DirectError(kind: "error", message: error.localizedDescription),
                previous: previousAccount
            )
        }
    }

    private static func fetch(_ account: DirectAccount) async throws -> UsageAccount {
        switch account.provider {
        case "codex": return try await fetchCodex(account)
        case "claude": return try await fetchClaude(account)
        case "grok": return try await fetchGrok(account)
        default: throw DirectError(kind: "parse", message: "Unsupported provider")
        }
    }

    private static func failedAccount(
        _ account: DirectAccount,
        error: DirectError,
        previous: UsageAccount?
    ) -> UsageAccount {
        let status = ["auth", "rate-limit"].contains(error.kind) ? error.kind : "error"
        return UsageAccount(
            id: account.id,
            provider: account.provider,
            label: previous?.label ?? account.label,
            plan: previous?.plan ?? account.plan,
            source: account.source,
            status: status,
            statusDetail: error.message,
            statusHint: signInHint(for: account.provider),
            windows: previous?.windows ?? [],
            extras: previous?.extras,
            updatedAt: iso(Date()),
            limitReached: previous?.limitReached
        )
    }

    private static func signInHint(for provider: String) -> String? {
        switch provider {
        case "codex": return "Run `codex login` to refresh this credential."
        case "claude": return "Run `claude` and /login with the subscription account."
        case "grok": return "Run `grok login` to refresh this credential."
        default: return nil
        }
    }

    private static func fetchCodex(_ account: DirectAccount) async throws -> UsageAccount {
        var headers = [
            "authorization": "Bearer \(account.token)",
            "user-agent": "codex_cli_rs/0.50.0",
        ]
        if let accountId = account.accountId, !accountId.isEmpty {
            headers["chatgpt-account-id"] = accountId
        }
        let root = try await fetchJSON(codexURL, headers: headers)
        let rateLimit = root["rate_limit"] as? [String: Any] ?? [:]
        let now = Date()
        var windows: [UsageWindow] = []
        if let primary = normalizeCodexWindow(rateLimit["primary_window"], position: "primary", now: now) {
            windows.append(primary)
        }
        if let secondary = normalizeCodexWindow(rateLimit["secondary_window"], position: "secondary", now: now) {
            windows.append(secondary)
        }
        guard !windows.isEmpty else {
            throw DirectError(kind: "parse", message: "No rate-limit windows in response")
        }

        let label = (root["email"] as? String) ?? account.email ?? account.label
        let plan = (root["plan_type"] as? String) ?? account.plan
        let limitReached = bool(rateLimit["limit_reached"]) || bool(rateLimit["allowed"]) == false
        return UsageAccount(
            id: account.id,
            provider: "codex",
            label: label,
            plan: plan,
            source: account.source,
            status: "ok",
            statusDetail: nil,
            statusHint: nil,
            windows: windows,
            extras: codexExtras(root),
            updatedAt: iso(Date()),
            limitReached: limitReached
        )
    }

    private static func normalizeCodexWindow(_ raw: Any?, position: String, now: Date) -> UsageWindow? {
        guard let object = raw as? [String: Any], let used = number(object["used_percent"]) else {
            return nil
        }
        let seconds = number(object["limit_window_seconds"]).map { Int($0.rounded()) }
        let resetAfter = number(object["reset_after_seconds"])
        var reset = parseDate(object["reset_at"])
        if reset == nil, let resetAfter {
            reset = now.addingTimeInterval(resetAfter)
        }
        let key = codexWindowKey(seconds: seconds, position: position)
        let label: String
        switch key {
        case "5h": label = "5-hour"
        case "week": label = "Weekly"
        default:
            let hours = max(1, Int((seconds ?? 0) / 3600))
            label = "\(hours)h"
        }
        return UsageWindow(
            key: key,
            label: label,
            usedPercent: round1(clamp(used)),
            remainingPercent: round1(clamp(100 - used)),
            windowSeconds: seconds,
            resetsAt: reset.map(iso),
            exhausted: used >= 100
        )
    }

    private static func codexWindowKey(seconds: Int?, position: String) -> String {
        guard let seconds, seconds > 0 else {
            return position == "primary" ? "5h" : "week"
        }
        if abs(seconds - 18_000) <= 1_800 { return "5h" }
        if abs(seconds - 604_800) <= 86_400 { return "week" }
        return "window-\(max(1, seconds / 3600))h"
    }

    private static func codexExtras(_ root: [String: Any]) -> [UsageExtra] {
        var extras: [UsageExtra] = []
        if let credits = root["credits"] as? [String: Any] {
            if bool(credits["unlimited"]) {
                extras.append(UsageExtra(kind: "text", label: "Credits", value: "Unlimited", items: nil))
            } else if let balance = number(credits["balance"]) {
                extras.append(UsageExtra(kind: "text", label: "Credits", value: formatAmount(balance), items: nil))
            }
            if bool(credits["overage_limit_reached"]) {
                extras.append(UsageExtra(kind: "warning", label: "Overage", value: "Limit reached", items: nil))
            }
        }
        if let spendControl = root["spend_control"] as? [String: Any], bool(spendControl["reached"]) {
            extras.append(UsageExtra(kind: "warning", label: "Spend control", value: "Reached", items: nil))
        }
        return extras
    }

    private static func fetchClaude(_ account: DirectAccount) async throws -> UsageAccount {
        let root = try await fetchJSON(claudeURL, headers: [
            "authorization": "Bearer \(account.token)",
            "anthropic-beta": "oauth-2025-04-20",
            "user-agent": "claude-cli/2.0.0 (external, cli)",
        ])
        var windows: [UsageWindow] = []
        pushClaudeWindow(&windows, root["five_hour"], key: "5h", label: "5-hour", seconds: 5 * 60 * 60)
        pushClaudeWindow(&windows, root["seven_day"], key: "week", label: "Weekly", seconds: 7 * 24 * 60 * 60)
        pushClaudeWindow(&windows, root["seven_day_opus"], key: "opus", label: "Opus weekly", seconds: 7 * 24 * 60 * 60)
        pushClaudeWindow(&windows, root["seven_day_sonnet"], key: "sonnet", label: "Sonnet weekly", seconds: 7 * 24 * 60 * 60)

        var extras: [UsageExtra] = []
        if let extra = root["extra_usage"] as? [String: Any], bool(extra["is_enabled"]) {
            pushClaudeWindow(&windows, extra, key: "extra", label: "Extra usage", seconds: 30 * 24 * 60 * 60)
            if let limit = number(extra["monthly_limit"]), limit > 0 {
                let used = number(extra["used_credits"]) ?? 0
                extras.append(UsageExtra(
                    kind: "text",
                    label: "Extra usage",
                    value: "\(formatAmount(used)) / \(formatAmount(limit))",
                    items: nil
                ))
            }
        }
        guard !windows.isEmpty else {
            throw DirectError(kind: "parse", message: "No usage windows in response")
        }
        return UsageAccount(
            id: account.id,
            provider: "claude",
            label: account.email ?? account.label,
            plan: account.plan,
            source: account.source,
            status: "ok",
            statusDetail: nil,
            statusHint: nil,
            windows: windows,
            extras: extras,
            updatedAt: iso(Date()),
            limitReached: windows.contains { $0.exhausted == true }
        )
    }

    private static func pushClaudeWindow(
        _ windows: inout [UsageWindow],
        _ raw: Any?,
        key: String,
        label: String,
        seconds: Int
    ) {
        guard let object = raw as? [String: Any], let used = number(object["utilization"]) else {
            return
        }
        windows.append(UsageWindow(
            key: key,
            label: label,
            usedPercent: round1(clamp(used)),
            remainingPercent: round1(clamp(100 - used)),
            windowSeconds: seconds,
            resetsAt: parseDate(object["resets_at"]).map(iso),
            exhausted: used >= 100
        ))
    }

    private static func fetchGrok(_ account: DirectAccount) async throws -> UsageAccount {
        let root = try await fetchJSON(grokURL, headers: [
            "authorization": "Bearer \(account.token)",
            "user-agent": "dsh-usage-monitor/1.1",
            "x-grok-client-mode": "cli",
        ])
        let config = (root["config"] as? [String: Any]) ?? root
        let hasPeriod = config["currentPeriod"] != nil || config["billingPeriodEnd"] != nil
        guard let used = number(config["creditUsagePercent"]) ?? (hasPeriod ? 0 : nil) else {
            throw DirectError(kind: "parse", message: "No credit usage in response")
        }
        let period = config["currentPeriod"] as? [String: Any]
        let start = parseDate(period?["start"]) ?? parseDate(config["billingPeriodStart"])
        let end = parseDate(period?["end"]) ?? parseDate(config["billingPeriodEnd"])
        var seconds = 7 * 24 * 60 * 60
        if let start, let end, end > start {
            seconds = max(60, Int(end.timeIntervalSince(start)))
        }
        let key = abs(seconds - 604_800) <= 86_400 ? "week" : "window-\(max(1, seconds / 3600))h"
        let label = key == "week" ? "Weekly" : "\(max(1, seconds / 3600))h"
        let window = UsageWindow(
            key: key,
            label: label,
            usedPercent: round1(clamp(used)),
            remainingPercent: round1(clamp(100 - used)),
            windowSeconds: seconds,
            resetsAt: end.map(iso),
            exhausted: used >= 100
        )

        var extras: [UsageExtra] = []
        if let products = config["productUsage"] as? [[String: Any]] {
            let items = products.compactMap { entry -> UsageProduct? in
                guard let product = entry["product"] as? String,
                      let percent = number(entry["usagePercent"]) else { return nil }
                return UsageProduct(label: productLabel(product), usedPercent: round1(clamp(percent)))
            }
            if !items.isEmpty {
                extras.append(UsageExtra(kind: "products", label: "Breakdown", value: nil, items: items))
            }
        }
        if let prepaid = number((config["prepaidBalance"] as? [String: Any])?["val"]), prepaid > 0 {
            extras.append(UsageExtra(kind: "text", label: "Prepaid", value: "$\(String(format: "%.2f", prepaid))", items: nil))
        }
        if let cap = number((config["onDemandCap"] as? [String: Any])?["val"]), cap > 0 {
            let usedAmount = number((config["onDemandUsed"] as? [String: Any])?["val"]) ?? 0
            extras.append(UsageExtra(
                kind: "text",
                label: "On-demand",
                value: "$\(String(format: "%.2f", usedAmount)) / $\(String(format: "%.2f", cap))",
                items: nil
            ))
        }

        return UsageAccount(
            id: account.id,
            provider: "grok",
            label: account.email ?? account.label,
            plan: account.plan,
            source: account.source,
            status: "ok",
            statusDetail: nil,
            statusHint: nil,
            windows: [window],
            extras: extras,
            updatedAt: iso(Date()),
            limitReached: used >= 100
        )
    }

    private static func productLabel(_ product: String) -> String {
        switch product {
        case "GrokBuild": return "Grok Build"
        case "GrokChat": return "Chat"
        case "Api": return "API"
        case "Imagine": return "Imagine"
        case "Voice": return "Voice"
        default:
            var value = product
            if let regex = try? NSRegularExpression(pattern: "([a-z])([A-Z])") {
                value = regex.stringByReplacingMatches(
                    in: value,
                    range: NSRange(value.startIndex..., in: value),
                    withTemplate: "$1 $2"
                )
            }
            return value.isEmpty ? "Other" : value
        }
    }

    // MARK: - HTTP

    private static func fetchJSON(_ url: URL, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw DirectError(kind: "timeout", message: "Request timed out")
        } catch {
            throw DirectError(kind: "network", message: sanitize(error.localizedDescription))
        }

        guard let http = response as? HTTPURLResponse else {
            throw DirectError(kind: "network", message: "Invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw DirectError(kind: "auth", message: "HTTP \(http.statusCode)")
        }
        if http.statusCode == 429 {
            throw DirectError(kind: "rate-limit", message: "HTTP 429")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DirectError(kind: "http", message: "HTTP \(http.statusCode)")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DirectError(kind: "parse", message: "Malformed JSON response")
        }
        return object
    }

    // MARK: - Claude token refresh

    private static func needsClaudeRefresh(_ account: DirectAccount) -> Bool {
        guard let expiresAt = account.expiresAt else { return false }
        return expiresAt < Date().timeIntervalSince1970 * 1000 + refreshSkewMs
    }

    private static func ensureClaudeToken(_ account: DirectAccount, force: Bool = false) async throws -> DirectAccount {
        guard account.provider == "claude", account.keychain, account.refreshToken != nil else {
            return account
        }
        if !force, !needsClaudeRefresh(account) {
            return account
        }
        guard let full = readClaudeKeychainFull(),
              let oauth = full["claudeAiOauth"] as? [String: Any] else {
            return account
        }
        let expiry = number(oauth["expiresAt"])
        let access = oauth["accessToken"] as? String
        if let access, access != account.token, let expiry,
           expiry > Date().timeIntervalSince1970 * 1000 + 60_000 {
            return DirectAccount(
                id: account.id,
                provider: account.provider,
                label: account.label,
                email: account.email,
                plan: account.plan,
                source: account.source,
                token: access,
                accountId: account.accountId,
                keychain: account.keychain,
                refreshToken: oauth["refreshToken"] as? String ?? account.refreshToken,
                expiresAt: expiry
            )
        }
        if !force, let expiry, expiry > Date().timeIntervalSince1970 * 1000 + refreshSkewMs {
            return account
        }
        return try await refreshClaudeAccount(account, full: full, oauth: oauth)
    }

    private static func refreshClaudeAccount(
        _ account: DirectAccount,
        full: [String: Any],
        oauth: [String: Any]
    ) async throws -> DirectAccount {
        guard let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else {
            throw DirectError(kind: "auth", message: "Claude refresh token missing")
        }
        var mutableOAuth = oauth
        var request = URLRequest(url: claudeTokenURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("claude-cli/2.1.310", forHTTPHeaderField: "user-agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": claudeClientID,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DirectError(kind: "auth", message: "Claude token refresh failed: \(sanitize(error.localizedDescription))")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DirectError(kind: "auth", message: "Claude token refresh failed (HTTP \(status))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            throw DirectError(kind: "auth", message: "Claude token refresh returned no token")
        }

        let nowMs = Date().timeIntervalSince1970 * 1000
        mutableOAuth["accessToken"] = access
        mutableOAuth["expiresAt"] = nowMs + (number(json["expires_in"]) ?? 28_800) * 1000
        if let newRefresh = json["refresh_token"] as? String, !newRefresh.isEmpty {
            mutableOAuth["refreshToken"] = newRefresh
        }
        if let refreshExpires = number(json["refresh_token_expires_in"]) {
            mutableOAuth["refreshTokenExpiresAt"] = nowMs + refreshExpires * 1000
        }
        var mutableFull = full
        mutableFull["claudeAiOauth"] = mutableOAuth
        try writeClaudeKeychain(mutableFull)

        return DirectAccount(
            id: account.id,
            provider: account.provider,
            label: account.label,
            email: account.email,
            plan: account.plan,
            source: account.source,
            token: access,
            accountId: account.accountId,
            keychain: account.keychain,
            refreshToken: mutableOAuth["refreshToken"] as? String,
            expiresAt: mutableOAuth["expiresAt"] as? Double
        )
    }

    private static func readClaudeKeychainFull() -> [String: Any]? {
        guard let text = try? run("/usr/bin/security", [
            "find-generic-password", "-s", claudeKeychainService, "-w"
        ]), let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func claudeKeychainAccount() -> String {
        guard let text = try? run("/usr/bin/security", [
            "find-generic-password", "-s", claudeKeychainService
        ]) else {
            return NSUserName()
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let regex = try? NSRegularExpression(pattern: #""acct"<blob>="([^"]*)""#),
              let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return NSUserName()
        }
        return String(text[valueRange])
    }

    private static func writeClaudeKeychain(_ full: [String: Any]) throws {
        guard let data = try? JSONSerialization.data(withJSONObject: full),
              let json = String(data: data, encoding: .utf8) else {
            throw DirectError(kind: "auth", message: "Could not encode the Claude credential")
        }
        do {
            _ = try run("/usr/bin/security", [
                "add-generic-password", "-U",
                "-s", claudeKeychainService,
                "-a", claudeKeychainAccount(),
                "-w", json,
            ])
        } catch {
            throw DirectError(kind: "auth", message: "Could not update the Claude Keychain item")
        }
    }

    // MARK: - Helpers

    private static func codexIdentity(_ token: String, fallbackAccountId: String?) -> (
        email: String?, userId: String?, teamId: String?, plan: String?, expiresAt: Double?
    ) {
        let claims = jwtClaims(token)
        let auth = claims["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        let profile = claims["https://api.openai.com/profile"] as? [String: Any] ?? [:]
        return (
            email: (claims["email"] as? String) ?? (profile["email"] as? String),
            userId: (auth["chatgpt_user_id"] as? String) ?? (auth["user_id"] as? String),
            teamId: (auth["chatgpt_account_id"] as? String) ?? fallbackAccountId,
            plan: auth["chatgpt_plan_type"] as? String,
            expiresAt: number(claims["exp"])
        )
    }

    private static func jwtClaims(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return [:] }
        var value = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        guard let data = Data(base64Encoded: value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func readJSON(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func dictionary(from value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        if let string = value as? String, let data = string.data(using: .utf8) {
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.doubleValue
        }
        if let string = value as? String, let number = Double(string) { return number }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool {
        (value as? Bool) ?? false
    }

    private static func clamp(_ value: Double) -> Double {
        max(0, min(100, value))
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func formatAmount(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.2f", value)
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let number = number(value) {
            let milliseconds = number < 1_000_000_000_000 ? number * 1000 : number
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if let number = Double(string) {
            let milliseconds = number < 1_000_000_000_000 ? number * 1000 : number
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        return UsageDate.parse(string)
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    private final class PipeBox: @unchecked Sendable {
        var data = Data()
    }


    private static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw DirectError(kind: "process", message: "Could not run \(executable)")
        }

        let group = DispatchGroup()
        let box = PipeBox()
        group.enter()
        DispatchQueue.global().async {
            box.data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw DirectError(kind: "timeout", message: "Local command timed out")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DirectError(kind: "process", message: "Local command failed")
        }
        return String(decoding: box.data, as: UTF8.self)
    }
}
