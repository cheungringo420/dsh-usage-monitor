import Foundation

enum UsageClient {
    static let endpoint = URL(string: "http://127.0.0.1:47821/state?token=uw-2b7c9f1e4a-4f6c-9a1e")!
    private static let cacheKey = "usage.snapshot.v1"

    static func fetch() async -> (snapshot: UsageSnapshot?, stale: Bool, error: String?) {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 3
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return (loadCache(), true, "helper-unavailable")
            }
            let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
            UserDefaults.standard.set(data, forKey: cacheKey)
            return (snapshot, isStale(snapshot), nil)
        } catch {
            return (loadCache(), true, error.localizedDescription)
        }
    }

    static func loadCache() -> UsageSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    static func isStale(_ snapshot: UsageSnapshot?) -> Bool {
        guard let date = UsageDate.parse(snapshot?.updatedAt) else { return true }
        return Date().timeIntervalSince(date) > 900
    }
}
