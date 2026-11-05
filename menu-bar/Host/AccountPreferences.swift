import Foundation

struct AccountPreferences {
    private static let excludedKey = "usageWidget.excludedAccountIDs"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var excludedAccountIDs: Set<String> {
        Set(defaults.stringArray(forKey: Self.excludedKey) ?? [])
    }

    func remove(_ id: String) {
        var ids = excludedAccountIDs
        ids.insert(id)
        defaults.set(ids.sorted(), forKey: Self.excludedKey)
    }

    func restoreAll() {
        defaults.removeObject(forKey: Self.excludedKey)
    }
}
