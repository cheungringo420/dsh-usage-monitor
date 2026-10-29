import AppKit
import SwiftUI

struct ProviderTheme: Identifiable {
    let id: String
    let name: String
    let accent: Color

    static let codex = ProviderTheme(
        id: "codex",
        name: "Codex",
        accent: Color(red: 0.06, green: 0.64, blue: 0.50)
    )
    static let claude = ProviderTheme(
        id: "claude",
        name: "Claude",
        accent: Color(red: 0.85, green: 0.46, blue: 0.34)
    )
    static let grok = ProviderTheme(
        id: "grok",
        name: "Grok",
        accent: Color(red: 0.55, green: 0.36, blue: 0.96)
    )
    static let other = ProviderTheme(
        id: "other",
        name: "Other",
        accent: Color(red: 0.55, green: 0.57, blue: 0.62)
    )

    static func theme(for provider: String) -> ProviderTheme {
        switch provider {
        case "codex": return .codex
        case "claude": return .claude
        case "grok": return .grok
        default: return .other
        }
    }
}

enum ProviderAsset {
    static func name(for provider: String) -> String? {
        switch provider {
        case "codex": return "ProviderCodex"
        case "claude": return "ProviderClaude"
        case "grok": return "ProviderGrok"
        default: return nil
        }
    }
}

/// The provider's actual brand mark (OpenAI knot, Claude starburst, Grok slash),
/// tinted with the provider accent. Falls back to an original glyph if no asset.
struct ProviderLogo: View {
    let provider: String
    var color: Color = .primary
    var size: CGFloat = 16

    var body: some View {
        if let name = ProviderAsset.name(for: provider) {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(color)
                .frame(width: size, height: size)
        } else {
            ProviderMark(provider: provider, color: color, size: size)
        }
    }
}

struct ProviderTile: View {
    let provider: String
    var size: CGFloat = 26

    private var theme: ProviderTheme { .theme(for: provider) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(theme.accent.opacity(0.13))
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.24), lineWidth: 0.7)
            ProviderLogo(provider: provider, color: theme.accent, size: size * 0.58)
        }
        .frame(width: size, height: size)
    }
}

struct ProviderMark: View {
    let provider: String
    let color: Color
    var size: CGFloat = 16

    var body: some View {
        Group {
            switch provider {
            case "codex":
                Image(systemName: "terminal.fill")
                    .font(.system(size: size * 0.82, weight: .semibold))
                    .foregroundStyle(color)
            case "claude":
                ClaudeStar()
                    .fill(color)
                    .frame(width: size, height: size)
            case "grok":
                GrokSlash()
                    .fill(color)
                    .frame(width: size, height: size)
            default:
                Image(systemName: "circle.grid.2x1.fill")
                    .font(.system(size: size * 0.7, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Eight tapered rays, an original mark in the spirit of Anthropic's starburst.
struct ClaudeStar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.30
        let spikeHalfWidth: CGFloat = 0.16

        for index in 0..<8 {
            let angle = CGFloat(index) * (.pi / 4) - (.pi / 2)
            let tip = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)
            let left = CGPoint(
                x: center.x + cos(angle - spikeHalfWidth) * inner,
                y: center.y + sin(angle - spikeHalfWidth) * inner
            )
            let right = CGPoint(
                x: center.x + cos(angle + spikeHalfWidth) * inner,
                y: center.y + sin(angle + spikeHalfWidth) * inner
            )
            if index == 0 {
                path.move(to: tip)
            } else {
                path.addLine(to: tip)
            }
            path.addLine(to: right)
            path.addLine(to: left)
            path.closeSubpath()
        }
        return path
    }
}

/// A bold angular X, an original mark for Grok.
struct GrokSlash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lineWidth = max(1.5, rect.width * 0.17)
        path.move(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.84))
        path.move(to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.width * 0.46, y: rect.height * 0.54))
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}
