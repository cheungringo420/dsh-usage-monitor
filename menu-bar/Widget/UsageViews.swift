import AppKit
import SwiftUI
import WidgetKit

extension UsageLevel {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warn: return .orange
        case .danger: return .red
        }
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                Color(nsColor: .windowBackgroundColor)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, !snapshot.accounts.isEmpty {
            switch family {
            case .systemSmall:
                SmallUsageView(entry: entry, snapshot: snapshot)
            case .systemLarge:
                LargeUsageView(entry: entry, snapshot: snapshot)
            default:
                MediumUsageView(entry: entry, snapshot: snapshot)
            }
        } else {
            EmptyUsageView()
        }
    }
}

private struct WidgetHeader: View {
    let entry: UsageEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 9, weight: .semibold))
            Text(L10n.title())
                .font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 2)
            if entry.stale {
                Text(L10n.stale())
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.orange)
            } else if let date = UsageDate.parse(entry.snapshot?.updatedAt) {
                Text(L10n.updated(date))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct UsageBar: View {
    let value: Double
    let level: UsageLevel
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(level.color)
                    .frame(width: geometry.size.width * max(0, min(1, value / 100)))
            }
        }
        .frame(height: height)
    }
}

private struct ResetCountdown: View {
    let window: UsageWindow
    var size: CGFloat = 8

    var body: some View {
        if let date = window.resetDate, date > Date() {
            Text(timerInterval: Date()...date, countsDown: true)
                .font(.system(size: size).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("—")
                .font(.system(size: size))
                .foregroundStyle(.secondary)
        }
    }
}

private struct WindowLine: View {
    let window: UsageWindow
    var compact: Bool = false
    var showAbsoluteReset: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(L10n.window(window))
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(L10n.left(window.remaining))
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .monospacedDigit()
            }
            UsageBar(value: window.remaining, level: window.level, height: compact ? 4 : 5)
            HStack(spacing: 3) {
                Text(L10n.used(window.used))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if showAbsoluteReset, let date = window.resetDate {
                    Text(L10n.reset(date))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    ResetCountdown(window: window, size: 8)
                }
            }
        }
    }
}

private struct ProviderColumn: View {
    let account: UsageAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(account.providerTitle)
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 2)
                if let plan = account.plan, !plan.isEmpty {
                    Text(plan.uppercased())
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(account.windows.prefix(2)) { window in
                WindowLine(window: window, compact: true)
            }
            if account.status == "auth" {
                Text(L10n.needsSignIn())
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            } else if account.status == "error" {
                Text(L10n.unavailable())
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SmallUsageView: View {
    let entry: UsageEntry
    let snapshot: UsageSnapshot

    private var rows: [(UsageAccount, UsageWindow)] {
        snapshot.accounts
            .flatMap { account in account.windows.map { (account, $0) } }
            .sorted { $0.1.remaining < $1.1.remaining }
            .prefix(2)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(entry: entry)
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(row.0.providerTitle)
                            .font(.system(size: 9, weight: .semibold))
                        Text(L10n.window(row.1))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 2)
                        Text(L10n.left(row.1.remaining))
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                    }
                    UsageBar(value: row.1.remaining, level: row.1.level, height: 5)
                    HStack(spacing: 2) {
                        Text(L10n.used(row.1.used))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 2)
                        ResetCountdown(window: row.1, size: 8)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(2)
    }
}

private struct MediumUsageView: View {
    let entry: UsageEntry
    let snapshot: UsageSnapshot

    private var accounts: [UsageAccount] {
        snapshot.accounts.sorted { left, right in
            let rank = ["codex": 0, "grok": 1]
            return (rank[left.provider] ?? 9) < (rank[right.provider] ?? 9)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(entry: entry)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(accounts.prefix(2).enumerated()), id: \.offset) { index, account in
                    if index > 0 {
                        Divider()
                            .overlay(Color.secondary.opacity(0.2))
                    }
                    ProviderColumn(account: account)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(2)
    }
}

private struct LargeUsageView: View {
    let entry: UsageEntry
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(entry: entry)

            ForEach(snapshot.accounts) { account in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(account.providerTitle)
                            .font(.system(size: 11, weight: .semibold))
                        Text(account.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        if let plan = account.plan, !plan.isEmpty {
                            Text(plan.uppercased())
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(account.windows) { window in
                        WindowLine(window: window, showAbsoluteReset: true)
                    }

                    if let extra = account.extras?.first(where: { ($0.items?.isEmpty == false) }) {
                        HStack(spacing: 5) {
                            ForEach(Array((extra.items ?? []).prefix(3).enumerated()), id: \.offset) { _, item in
                                Text("\(item.label) \(Int(item.usedPercent.rounded()))%")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1), in: Capsule())
                            }
                        }
                        .padding(.top, 1)
                    }

                    if account.status == "auth" {
                        Text(L10n.needsSignIn())
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    } else if account.status == "error" {
                        Text(L10n.unavailable())
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)
            HStack {
                Text(entry.error == nil ? "~/.dsh/usage-monitor" : (entry.error ?? ""))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("127.0.0.1:47821")
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(2)
    }
}

private struct EmptyUsageView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.secondary)
            Text(L10n.noData())
                .font(.system(size: 12, weight: .semibold))
            Text(L10n.openHelper())
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
