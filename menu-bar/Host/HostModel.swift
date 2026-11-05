import AppKit
import Foundation
import ServiceManagement
import WidgetKit

enum MenuBarSelection: Hashable, CaseIterable, Identifiable {
    case all
    case codex
    case claude
    case grok
    case account(String)

    static let allCases: [MenuBarSelection] = [.all, .codex, .claude, .grok]

    init?(rawValue: String) {
        switch rawValue {
        case "all": self = .all
        case "codex": self = .codex
        case "claude": self = .claude
        case "grok": self = .grok
        default:
            guard rawValue.hasPrefix("account:"), rawValue.count > 8 else { return nil }
            self = .account(String(rawValue.dropFirst(8)))
        }
    }

    var rawValue: String {
        switch self {
        case .all: return "all"
        case .codex: return "codex"
        case .claude: return "claude"
        case .grok: return "grok"
        case .account(let id): return "account:\(id)"
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Worst of all"
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .grok: return "Grok"
        case .account: return "Selected account"
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
    @Published private(set) var excludedAccountIDs: Set<String>
    @Published private(set) var signingInAccountID: String?
    @Published private(set) var accountActionError: String?
    @Published var menuBarSelection: MenuBarSelection {
        didSet {
            defaults.set(menuBarSelection.rawValue, forKey: Self.menuBarSelectionKey)
        }
    }

    private static let menuBarSelectionKey = "usageWidget.menuBarSelection"
    private let defaults: UserDefaults
    private let server = StateServer()
    private let accountPreferences: AccountPreferences
    private var signInSession: CodexSignIn.Session?
    private var refreshAfterSignIn = false
    private var started = false
    private var scheduler: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let preferences = AccountPreferences(defaults: defaults)
        accountPreferences = preferences
        excludedAccountIDs = preferences.excludedAccountIDs
        let saved = defaults.string(forKey: Self.menuBarSelectionKey)
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
        refresh()
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard let self else { return }
                self.refresh()
            }
        }
    }

    /// Read the local provider credentials and call the usage APIs directly.
    /// No DeepSeek Harness install is required for the menu-bar app.
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let previous = snapshot
        let excluded = excludedAccountIDs

        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                await DirectUsageEngine.collect(previous: previous, excludedAccountIDs: excluded)
            }.value
            self.snapshot = result.snapshot
            self.lastUpdated = UsageDate.parse(result.snapshot.updatedAt) ?? Date()
            self.lastError = result.error
            self.refreshing = false
            self.server.reloadWidgets()
            if self.refreshAfterSignIn {
                self.refreshAfterSignIn = false
                self.refresh()
            }
        }
    }

    func reload(notify: Bool = true) {
        if let snapshot = UsageStateStore.decoded() {
            self.snapshot = UsageSnapshot(
                version: snapshot.version, updatedAt: snapshot.updatedAt,
                accounts: snapshot.accounts.filter { !excludedAccountIDs.contains($0.id) }
            )
            self.lastUpdated = UsageDate.parse(snapshot.updatedAt)
            self.lastError = nil
        } else {
            self.snapshot = nil
            self.lastUpdated = nil
            self.lastError = nil
        }
        if notify {
            server.reloadWidgets()
        }
    }

    var menuBarProvider: String? {
        if case .account(let id) = menuBarSelection {
            return snapshot?.accounts.first(where: { $0.id == id })?.provider
                ?? id.split(separator: ":").first.map(String.init)
        }
        if menuBarSelection != .all { return menuBarSelection.rawValue }
        return menuBarWorst?.provider
    }

    private var menuBarAccounts: [UsageAccount] {
        guard let snapshot else { return [] }
        if case .account(let id) = menuBarSelection {
            return snapshot.accounts.filter { $0.id == id }
        }
        if menuBarSelection == .all { return snapshot.accounts }
        return snapshot.accounts.filter { $0.provider == menuBarSelection.rawValue }
    }

    private var menuBarWorst: (provider: String, remaining: Double)? {
        var best: (provider: String, remaining: Double)?
        for account in menuBarAccounts {
            guard account.status == "ok" else { continue }
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

    func removeAccount(_ account: UsageAccount) {
        guard !refreshing, signingInAccountID == nil else { return }
        if menuBarSelection == .account(account.id) { menuBarSelection = .all }
        accountPreferences.remove(account.id)
        excludedAccountIDs = accountPreferences.excludedAccountIDs
        guard let snapshot else { return }
        let filtered = UsageSnapshot(
            version: snapshot.version, updatedAt: snapshot.updatedAt,
            accounts: snapshot.accounts.filter { !excludedAccountIDs.contains($0.id) }
        )
        self.snapshot = filtered
        do {
            try UsageStateStore.save(filtered)
            accountActionError = nil
            server.reloadWidgets()
        } catch {
            accountActionError = "Could not save removed accounts: \(error.localizedDescription)"
        }
    }

    func restoreRemovedAccounts() {
        guard !refreshing else { return }
        accountPreferences.restoreAll()
        excludedAccountIDs = []
        accountActionError = nil
        refresh()
    }

    func signInAgain(_ account: UsageAccount) {
        guard account.provider == "codex", signingInAccountID == nil, !refreshing else { return }
        accountActionError = nil
        signingInAccountID = account.id
        let session = CodexSignIn.Session()
        signInSession = session
        do {
            try session.start(accountID: account.id) { [weak self] result in
                guard let self else { return }
                self.signingInAccountID = nil
                self.signInSession = nil
                switch result {
                case .success:
                    if self.refreshing { self.refreshAfterSignIn = true }
                    else { self.refresh() }
                case .failure(let error):
                    self.accountActionError = error.localizedDescription
                }
            }
        } catch {
            signingInAccountID = nil
            signInSession = nil
            accountActionError = error.localizedDescription
        }
    }

    func cancelSignIn() {
        signInSession?.cancel()
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
        if FileManager.default.fileExists(atPath: UsageStateStore.fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([UsageStateStore.fileURL])
        } else {
            NSWorkspace.shared.open(UsageStateStore.supportDirectory)
        }
    }

    func quit() {
        signInSession?.cancel()
        NSApp.terminate(nil)
    }
}
