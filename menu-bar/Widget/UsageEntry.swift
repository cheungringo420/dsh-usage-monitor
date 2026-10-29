import Foundation
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let stale: Bool
    let error: String?

    static var placeholder: UsageEntry {
        UsageEntry(date: Date(), snapshot: sample, stale: false, error: nil)
    }

    static let sample: UsageSnapshot = {
        let json = #"""
        {
          "version": 1,
          "updatedAt": "2026-10-26T12:43:27.948Z",
          "accounts": [
            {
              "id": "codex:sample",
              "provider": "codex",
              "label": "codex@example.com",
              "plan": "team",
              "source": "cli",
              "status": "ok",
              "windows": [
                {"key":"5h","label":"5-hour","usedPercent":0,"remainingPercent":100,"windowSeconds":18000,"resetsAt":"2026-10-26T17:16:22.000Z"},
                {"key":"week","label":"Weekly","usedPercent":9,"remainingPercent":91,"windowSeconds":604800,"resetsAt":"2026-11-02T05:59:32.000Z"}
              ],
              "extras": [],
              "limitReached": false
            },
            {
              "id": "grok:sample",
              "provider": "grok",
              "label": "grok@example.com",
              "source": "cli",
              "status": "ok",
              "windows": [
                {"key":"week","label":"Weekly","usedPercent":90,"remainingPercent":10,"windowSeconds":604800,"resetsAt":"2026-10-27T04:18:52.117Z"}
              ],
              "extras": [
                {"kind":"products","label":"Breakdown","items":[
                  {"label":"Grok Build","usedPercent":89},
                  {"label":"Chat","usedPercent":1}
                ]}
              ],
              "limitReached": false
            }
          ]
        }
        """#
        return (try? JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))) ?? UsageSnapshot(version: 1, updatedAt: nil, accounts: [])
    }()
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if let cached = UsageClient.loadCache() {
            completion(UsageEntry(date: Date(), snapshot: cached, stale: UsageClient.isStale(cached), error: nil))
        } else {
            completion(.placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let result = await UsageClient.fetch()
            let entry = UsageEntry(date: Date(), snapshot: result.snapshot, stale: result.stale, error: result.error)
            let next = Date().addingTimeInterval(300)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}
