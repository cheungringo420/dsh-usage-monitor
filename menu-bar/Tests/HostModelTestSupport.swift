import Foundation

extension UsageStateStore {
    static var fileURL: URL { supportDirectory.appendingPathComponent("snapshot.json") }
    static func decoded() -> UsageSnapshot? { savedSnapshots.last }
}

final class StateServer {
    var onStateChanged: (() -> Void)?
    var onStatusChange: ((Bool) -> Void)?
    func start() { }
    func reloadWidgets() { }
}
