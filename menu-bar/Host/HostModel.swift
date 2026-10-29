import AppKit
import Foundation
import ServiceManagement
import WidgetKit

enum MenuBarSelection: String, CaseIterable, Identifiable {
    case all
    case codex
    case claude
    case grok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Worst of all"
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .grok: return "Grok"
        }
    }
}

@MainActor
final class HostModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var serverRunning = false
    @Published private(set) var refreshing = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var lastUpdated: Date?
    @Published var menuBarSelection: MenuBarSelection {
        didSet {
            UserDefaults.standard.set(menuBarSelection.rawValue, forKey: Self.menuBarSelectionKey)
        }
    }

    private static let menuBarSelectionKey = "usageWidget.menuBarSelection"
    private let server = StateServer()
    private var started = false

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.menuBarSelectionKey)
        menuBarSelection = saved.flatMap(MenuBarSelection.init(rawValue:)) ?? .all
    }

    func start() {
        guard !started else { return }
        started = true
        server.onStateChanged = { [weak self] in
            Task { @MainActor in self?.reload(notify: false) }
        }
        server.onStatusChange = { [weak self] running in
            Task { @MainActor in self?.serverRunning = running }
        }
        server.start()
        reload(notify: true)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Ask the DSH plugin to fetch all providers now. The helper can't use the
    /// browser-authenticated `/api` bridge, so the request travels as a file.
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let baseline = lastUpdated

        do {
            let payload = "\(Date().timeIntervalSince1970)\n"
            guard let data = payload.data(using: .utf8) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: UsageStateStore.refreshRequestURL, options: .atomic)
        } catch {
            lastError = "Could not ask DeepSeek Harness to refresh: \(error.localizedDescription)"
            refreshing = false
            return
        }

        Task { @MainActor in
            defer {
                refreshing = false
                server.reloadWidgets()
            }
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                reload(notify: false)
                if lastUpdated != baseline {
                    return
                }
            }
        }
    }

    func reload(notify: Bool = true) {
        if let snapshot = UsageStateStore.decoded() {
            self.snapshot = snapshot
            self.lastUpdated = UsageDate.parse(snapshot.updatedAt)
            self.lastError = nil
        } else {
            self.snapshot = nil
            self.lastUpdated = nil
            self.lastError = "Waiting for ~/.dsh/usage-monitor/state.json"
        }
        if notify {
            server.reloadWidgets()
        }
    }

    var menuBarProvider: String? {
        if menuBarSelection != .all { return menuBarSelection.rawValue }
        return menuBarWorst?.provider
    }

    private var menuBarAccounts: [UsageAccount] {
        guard let snapshot else { return [] }
        if menuBarSelection == .all { return snapshot.accounts }
        return snapshot.accounts.filter { $0.provider == menuBarSelection.rawValue }
    }

    private var menuBarWorst: (provider: String, remaining: Double)? {
        var best: (provider: String, remaining: Double)?
        for account in menuBarAccounts {
            guard let remaining = account.windows.map(\.remaining).min() else { continue }
            if best == nil || remaining < best!.remaining {
                best = (account.provider, remaining)
            }
        }
        return best
    }

    var menuLabel: String {
        guard let worst = menuBarWorst else { return "—" }
        return "\(Int(worst.remaining.rounded()))%"
    }

    var isStale: Bool {
        guard let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 900
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            lastError = "Login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func openStateFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([UsageStateStore.fileURL])
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
