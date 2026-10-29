import Foundation
import Network
import WidgetKit

enum UsageStateStore {
    static var dshHome: URL {
        if let value = ProcessInfo.processInfo.environment["DSH_HOME"], !value.isEmpty {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh")
    }

    static var fileURL: URL {
        dshHome.appendingPathComponent("usage-monitor/state.json")
    }

    static var refreshRequestURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("refresh.request")
    }

    static func readData() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    /// The DSH plugin stores accounts as an id-keyed object; the widget and the
    /// helper both consume the array form.
    static func snapshotData() -> Data? {
        guard let data = readData() else { return nil }
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        if let accounts = object["accounts"] as? [String: Any] {
            object["accounts"] = accounts.values.sorted { left, right in
                let leftObject = left as? [String: Any] ?? [:]
                let rightObject = right as? [String: Any] ?? [:]
                let leftRank = rank(leftObject["provider"] as? String)
                let rightRank = rank(rightObject["provider"] as? String)
                if leftRank != rightRank { return leftRank < rightRank }
                return (leftObject["label"] as? String ?? "") < (rightObject["label"] as? String ?? "")
            }
        }
        return try? JSONSerialization.data(withJSONObject: object)
    }

    private static func rank(_ provider: String?) -> Int {
        switch provider {
        case "codex": return 0
        case "claude": return 1
        case "grok": return 2
        default: return 9
        }
    }

    static func decoded() -> UsageSnapshot? {
        guard let data = snapshotData() else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}

/// Loopback-only JSON endpoint for the widget extension, plus a poller that
/// asks WidgetKit to reload when the DSH plugin writes a new snapshot.
final class StateServer {
    static let port: UInt16 = 47821
    static let token = "uw-2b7c9f1e4a-4f6c-9a1e"

    private let queue = DispatchQueue(label: "io.github.cheungringo420.usagemonitor.server")
    private var listener: NWListener?
    private var pollTimer: Timer?
    private var lastModification: Date?
    private(set) var isRunning = false

    var onStateChanged: (() -> Void)?
    var onStatusChange: ((Bool) -> Void)?

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .init(rawValue: Self.port)!)
        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.onStatusChange?(true)
                        print("[usage-widget] listening on 127.0.0.1:\(Self.port)")
                    case .failed(let error):
                        self?.isRunning = false
                        self?.onStatusChange?(false)
                        print("[usage-widget] listener failed: \(error)")
                    case .cancelled:
                        self?.isRunning = false
                        self?.onStatusChange?(false)
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            isRunning = false
            onStatusChange?(false)
            print("[usage-widget] could not start listener: \(error)")
        }

        lastModification = modificationDate()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: UsageStateStore.fileURL.path)[.modificationDate]) as? Date
    }

    private func poll() {
        let current = modificationDate()
        guard current != lastModification else { return }
        lastModification = current
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?()
            self?.reloadWidgets()
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self, let data, !data.isEmpty, error == nil else {
                connection.cancel()
                return
            }
            let response = self.response(for: data)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for data: Data) -> Data {
        let request = String(decoding: data, as: UTF8.self)
        guard let requestLine = request.split(separator: "\r\n").first else {
            return httpResponse(status: "400 Bad Request", body: #"{"error":"bad-request"}"#)
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: "400 Bad Request", body: #"{"error":"bad-request"}"#)
        }
        let target = String(parts[1])
        guard let components = URLComponents(string: "http://127.0.0.1\(target)") else {
            return httpResponse(status: "400 Bad Request", body: #"{"error":"bad-request"}"#)
        }
        guard components.path == "/state" else {
            return httpResponse(status: "404 Not Found", body: #"{"error":"not-found"}"#)
        }
        let token = components.queryItems?.first(where: { $0.name == "token" })?.value
        guard token == Self.token else {
            return httpResponse(status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
        }
        guard let data = UsageStateStore.snapshotData() else {
            return httpResponse(status: "503 Service Unavailable", body: #"{"error":"no-state"}"#)
        }
        return httpResponse(status: "200 OK", body: String(decoding: data, as: UTF8.self))
    }

    private func httpResponse(status: String, body: String) -> Data {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        return response
    }
}
