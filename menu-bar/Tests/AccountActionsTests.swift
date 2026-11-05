import Foundation

private struct TestFailure: Error { let message: String }
private func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(message: message) }
}

@main
struct AccountActionsTests {
    static func main() throws {
        let suite = "UsageMonitorAccountTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AccountPreferences(defaults: defaults)
        preferences.remove("codex:user-two")
        let reloaded = AccountPreferences(defaults: UserDefaults(suiteName: suite)!)
        try check(reloaded.excludedAccountIDs == ["codex:user-two"], "Removed account must stay removed after reloading preferences")
        preferences.restoreAll()
        try check(reloaded.excludedAccountIDs.isEmpty, "Restore must make removed accounts discoverable again")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usage-login-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pending = root.appendingPathComponent("pending.json")
        let destination = root.appendingPathComponent("account/auth.json")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("existing credential".utf8)
        try original.write(to: destination)
        let wrong = try auth(user: "user-one")
        try wrong.write(to: pending)
        do {
            try CodexSignIn.installCredential(from: pending, accountID: "codex:user-two", destination: destination)
            throw TestFailure(message: "Wrong account must not be accepted")
        } catch is CodexSignIn.SignInError { }
        try check(try Data(contentsOf: destination) == original, "Wrong-account login must leave existing credential untouched")

        let matching = try auth(user: "user-two")
        try matching.write(to: pending)
        try CodexSignIn.installCredential(from: pending, accountID: "codex:user-two", destination: destination)
        try check(try Data(contentsOf: destination) == matching, "Matching login must install its credential")
        let permissions = try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
        try check(permissions?.intValue == 0o600, "Stored credentials must be private")
        try check(!CodexSignIn.directoryName(for: "codex:../../outside").contains("/"), "Account IDs must not escape the credential directory")
        print("PASS: persistent removal, restore, wrong-account protection, matching login, credential permissions")
    }

    private static func auth(user: String) throws -> Data {
        let claims: [String: Any] = [
            "exp": 4102444800,
            "https://api.openai.com/auth": ["chatgpt_user_id": user, "chatgpt_account_id": "same-workspace"],
            "https://api.openai.com/profile": ["email": user + "@example.test"]
        ]
        let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
        let token = "header." + payload + ".signature"
        return try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": ["access_token": token]])
    }
}
