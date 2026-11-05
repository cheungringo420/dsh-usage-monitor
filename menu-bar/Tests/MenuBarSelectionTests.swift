import Foundation

private struct TestFailure: Error { let message: String }
private func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(message: message) }
}

@main
struct MenuBarSelectionTests {
    @MainActor
    static func main() throws {
        let suite = "UsageMonitorSelectionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = account("codex:first", provider: "codex", remaining: 80)
        let second = account("codex:second", provider: "codex", remaining: 25)
        let expired = account("codex:expired", provider: "codex", remaining: 1, status: "auth")
        let claude = account("claude:code", provider: "claude", remaining: 60)
        try UsageStateStore.save(UsageSnapshot(version: 1, updatedAt: nil, accounts: [first, second, expired, claude]))
        let model = HostModel(defaults: defaults)
        model.reload(notify: false)
        try check(model.menuLabel == "25%", "All providers must ignore expired cached quota")
        model.menuBarSelection = .claude
        try check(model.menuLabel == "60%", "Provider selection must show that provider's quota")
        model.menuBarSelection = .account(first.id)
        try check(model.menuLabel == "80%", "Account selection must show only the selected account")
        try check(model.menuBarProvider == "codex", "Account selection must retain its provider icon")
        let relaunched = HostModel(defaults: UserDefaults(suiteName: suite)!)
        relaunched.reload(notify: false)
        try check(relaunched.menuBarSelection == .account("codex:first"), "Account selection must survive restart")
        try check(relaunched.menuLabel == "80%", "Restored selection must resolve the same account quota")
        model.menuBarSelection = .account(expired.id)
        try check(model.menuLabel == "—", "Expired selected account must not display stale quota as current")
        model.menuBarSelection = .account(first.id)
        model.removeAccount(first)
        try check(model.menuBarSelection == .all, "Removing the selected account must reset to all providers")
        try check(model.snapshot?.accounts.contains(where: { $0.id == first.id }) == false, "Removed selected account must leave the visible snapshot")
        print("PASS: provider/account selection, persistence, expired quota exclusion, selected-account removal")
    }

    private static func account(_ id: String, provider: String, remaining: Double, status: String = "ok") -> UsageAccount {
        UsageAccount(
            id: id, provider: provider, label: id, plan: nil, source: "fixture", status: status,
            statusDetail: nil, statusHint: nil,
            windows: [UsageWindow(key: "5h", label: "5-hour", usedPercent: 100 - remaining, remainingPercent: remaining, windowSeconds: 18000, resetsAt: nil, exhausted: false)],
            extras: nil, updatedAt: nil, limitReached: false
        )
    }
}
