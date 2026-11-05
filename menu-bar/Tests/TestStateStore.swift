import Foundation

/// Standalone test substitute; never reads or writes the installed app's store.
enum UsageStateStore {
    static var supportDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("UsageMonitorTests-\(UUID().uuidString)", isDirectory: true)
    static var savedSnapshots: [UsageSnapshot] = []

    static func save(_ snapshot: UsageSnapshot) throws {
        savedSnapshots.append(snapshot)
    }
}
