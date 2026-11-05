import AppKit
import SwiftUI

/// Exercise constrained minimum sizing as well as the view's ideal size.
private struct MinimumSizeLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(ProposedViewSize(width: 380, height: 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

@main
struct MenuLayoutTests {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let suite = "UsageMonitorLayoutTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let accounts = ["codex:first", "codex:second", "claude:code", "grok:first"].map { id in
            UsageAccount(
                id: id, provider: String(id.split(separator: ":")[0]), label: id,
                plan: nil, source: "fixture", status: id == "codex:second" ? "auth" : "ok",
                statusDetail: nil, statusHint: nil,
                windows: [UsageWindow(key: "5h", label: "5-hour", usedPercent: 20, remainingPercent: 80, windowSeconds: 18000, resetsAt: nil, exhausted: false)],
                extras: nil, updatedAt: nil, limitReached: false
            )
        }
        try UsageStateStore.save(UsageSnapshot(version: 1, updatedAt: nil, accounts: accounts))
        let model = HostModel(defaults: defaults)
        model.reload(notify: false)
        let view = NSHostingView(rootView: MinimumSizeLayout { HostMenuView(model: model) })
        let size = view.fittingSize
        guard size.height >= 400 else {
            print("FAIL: Account list collapsed during intrinsic sizing; menu height = \(size.height)")
            exit(1)
        }
        print("PASS: Account list has visible intrinsic height; menu size = \(size)")
    }
}
