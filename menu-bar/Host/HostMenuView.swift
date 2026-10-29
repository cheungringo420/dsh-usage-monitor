import AppKit
import SwiftUI

struct HostMenuView: View {
    @ObservedObject var model: HostModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let snapshot = model.snapshot, !snapshot.accounts.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(sections(for: snapshot.accounts)) { section in
                            ProviderSectionView(section: section, now: context.date)
                        }
                    }
                }
            } else {
                emptyState
            }

            Divider()
                .opacity(0.55)

            footer
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Usage Monitor")
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                statusPill
                refreshButton
            }
        }
    }

    private var refreshButton: some View {
        Button {
            model.refresh()
        } label: {
            HStack(spacing: 4) {
                if model.refreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.75)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                Text(model.refreshing ? "Refreshing" : "Refresh")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(model.refreshing)
        .opacity(model.refreshing ? 0.7 : 1)
        .help("Ask DeepSeek Harness to fetch fresh provider usage")
        .accessibilityLabel("Refresh")
    }

    private var subtitle: String {
        if model.refreshing { return "Refreshing providers…" }
        guard let snapshot = model.snapshot, !snapshot.accounts.isEmpty else {
            return "Waiting for DeepSeek Harness"
        }
        let updated = L10n.updated(model.lastUpdated ?? Date())
        return "\(L10n.accountCount(snapshot.accounts.count)) · \(updated)"
    }

    private var statusPill: some View {
        let state = statusState
        return HStack(spacing: 4) {
            Circle()
                .fill(state.color)
                .frame(width: 5, height: 5)
            Text(state.label)
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.4)
        }
        .foregroundStyle(state.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(state.color.opacity(0.12), in: Capsule())
    }

    private var statusState: (label: String, color: Color) {
        if model.snapshot == nil { return ("NO DATA", .secondary) }
        if model.isStale { return ("STALE", .orange) }
        return ("LIVE", .green)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No usage data yet")
                .font(.system(size: 13, weight: .semibold))
            Text(model.lastError ?? "Open DeepSeek Harness with the Usage Monitor plugin.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.6)
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Menu bar")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Menu bar", selection: $model.menuBarSelection) {
                    ForEach(MenuBarSelection.allCases) { selection in
                        Text(selection.title).tag(selection)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 136)
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(model.serverRunning ? Color.green : Color.orange)
                    .frame(width: 5, height: 5)
                Text(model.serverRunning ? "Data server :47821" : "Data server offline")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 10.5))

            HStack(spacing: 8) {
                Button("Reveal state file") { model.openStateFolder() }
                    .buttonStyle(.link)
                    .font(.system(size: 10.5))
                Spacer()
                Button("Quit") { model.quit() }
                    .buttonStyle(.link)
                    .font(.system(size: 12.5, weight: .medium))
            }
        }
    }

    private func sections(for accounts: [UsageAccount]) -> [ProviderSection] {
        var groups: [String: [UsageAccount]] = [:]
        for account in accounts {
            groups[account.provider, default: []].append(account)
        }

        var result: [ProviderSection] = []
        for id in ["codex", "claude", "grok"] {
            guard let list = groups.removeValue(forKey: id), !list.isEmpty else { continue }
            result.append(ProviderSection(theme: .theme(for: id), accounts: sorted(list)))
        }
        for (id, list) in groups where !list.isEmpty {
            result.append(ProviderSection(theme: .theme(for: id), accounts: sorted(list)))
        }
        return result
    }

    private func sorted(_ accounts: [UsageAccount]) -> [UsageAccount] {
        accounts.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}

private struct ProviderSection: Identifiable {
    let theme: ProviderTheme
    let accounts: [UsageAccount]

    var id: String { theme.id }
}

private struct ProviderSectionView: View {
    let section: ProviderSection
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderTile(provider: section.theme.id, size: 24)
                Text(section.theme.name)
                    .font(.system(size: 13, weight: .semibold))

                if section.accounts.count > 1 {
                    Text("\(section.accounts.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }

                Spacer(minLength: 8)
                Rectangle()
                    .fill(section.theme.accent.opacity(0.22))
                    .frame(width: 42, height: 1)
            }

            VStack(spacing: 8) {
                ForEach(section.accounts) { account in
                    AccountCardView(account: account, theme: section.theme, now: now)
                }
            }
        }
    }
}

private struct AccountCardView: View {
    let account: UsageAccount
    let theme: ProviderTheme
    let now: Date

    private var statusColor: Color {
        if account.status == "error" { return .red }
        if account.status == "auth" { return .orange }
        if account.windows.contains(where: { $0.remaining <= 10 }) { return .orange }
        return .green
    }

    private var statusHelp: String {
        if account.status == "error" { return L10n.unavailable() }
        if account.status == "auth" { return L10n.needsSignIn() }
        return L10n.live()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(account.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let plan = account.plan, !plan.isEmpty {
                    Text(plan.uppercased())
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                }

                Spacer(minLength: 4)
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                    .help(statusHelp)
            }

            if account.windows.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.statusDetail ?? L10n.noData())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = account.statusHint {
                        Text(hint)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ForEach(account.windows) { window in
                WindowRowView(window: window, theme: theme, now: now)
            }

            if account.status != "ok", !account.windows.isEmpty {
                Text(account.statusDetail ?? L10n.unavailable())
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 13)
        .padding(.trailing, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.6)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(theme.accent.opacity(0.85))
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 3)
        }
    }
}

private struct WindowRowView: View {
    let window: UsageWindow
    let theme: ProviderTheme
    let now: Date

    private var remaining: Double { max(0, min(100, window.remainingPercent)) }

    private var fillColor: Color {
        switch window.level {
        case .ok: return theme.accent
        case .warn: return .orange
        case .danger: return .red
        }
    }

    private var resetText: String {
        guard let date = window.resetDate else { return "—" }
        return L10n.resetDetail(date, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(L10n.window(window))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(L10n.left(remaining))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(fillColor)
                        .frame(width: geometry.size.width * (remaining / 100))
                }
            }
            .frame(height: 5)

            HStack(spacing: 4) {
                Text(L10n.used(window.used))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(resetText)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
