import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = HostModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}

@main
struct UsageWidgetHostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            HostMenuView(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: HostModel

    private var providerName: String {
        guard let provider = model.menuBarProvider else { return "all providers" }
        return ProviderTheme.theme(for: provider).name
    }

    var body: some View {
        HStack(spacing: 3) {
            MenuBarProviderIcon(provider: model.menuBarProvider)
            Text(model.menuLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .accessibilityLabel("Usage Monitor, \(providerName), \(model.menuLabel)")
    }
}


private struct MenuBarProviderIcon: View {
    let provider: String?

    var body: some View {
        if let provider, let image = MenuBarIconCache.image(for: provider) {
            Image(nsImage: image)
                .renderingMode(.original)
        } else {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 11, weight: .medium))
        }
    }
}

@MainActor
private enum MenuBarIconCache {
    private static var cache: [String: NSImage] = [:]

    static func image(for provider: String) -> NSImage? {
        if let cached = cache[provider] { return cached }
        let theme = ProviderTheme.theme(for: provider)
        let renderer = ImageRenderer(
            content: ProviderLogo(provider: provider, color: theme.accent, size: 13)
                .frame(width: 13, height: 13)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        cache[provider] = image
        return image
    }
}
