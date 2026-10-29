import SwiftUI
import WidgetKit

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

struct UsageWidget: Widget {
    let kind: String = "UsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Usage Monitor")
        .description("Codex and Grok remaining quota, reset times, and refill status.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
