import Foundation

struct UsageSnapshot: Codable, Sendable {
    let version: Int?
    let updatedAt: String?
    let accounts: [UsageAccount]
}

struct UsageAccount: Codable, Identifiable, Sendable {
    let id: String
    let provider: String
    let label: String
    let plan: String?
    let source: String?
    let status: String
    let statusDetail: String?
    let statusHint: String?
    let windows: [UsageWindow]
    let extras: [UsageExtra]?
    let updatedAt: String?
    let limitReached: Bool?

    var providerTitle: String { L10n.provider(provider) }
    var worstRemaining: Double { windows.map(\.remaining).min() ?? 100 }
}

struct UsageWindow: Codable, Identifiable, Sendable {
    let key: String
    let label: String
    let usedPercent: Double
    let remainingPercent: Double
    let windowSeconds: Int?
    let resetsAt: String?
    let exhausted: Bool?

    var id: String { "\(key)-\(resetsAt ?? "none")" }
    var remaining: Double { max(0, min(100, remainingPercent)) }
    var used: Double { max(0, min(100, usedPercent)) }
    var resetDate: Date? { UsageDate.parse(resetsAt) }
    var level: UsageLevel {
        if remaining <= 10 { return .danger }
        if remaining <= 30 { return .warn }
        return .ok
    }
}

struct UsageExtra: Codable, Sendable {
    let kind: String?
    let label: String
    let value: String?
    let items: [UsageProduct]?
}

struct UsageProduct: Codable, Sendable {
    let label: String
    let usedPercent: Double
}

enum UsageLevel {
    case ok, warn, danger
}

enum UsageDate {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return withFractional.date(from: value) ?? plain.date(from: value)
    }
}

enum L10n {
    static var isChinese: Bool {
        Locale.current.language.languageCode?.identifier == "zh"
    }

    static func title() -> String {
        isChinese ? "用量" : "Usage"
    }

    static func provider(_ id: String) -> String {
        switch id {
        case "codex": return "Codex"
        case "grok": return "Grok"
        case "claude": return "Claude"
        default: return id.capitalized
        }
    }

    static func window(_ window: UsageWindow) -> String {
        switch window.key {
        case "5h": return isChinese ? "5 小時" : "5-hour"
        case "week": return isChinese ? "本週" : "Weekly"
        case "day": return isChinese ? "每日" : "Daily"
        case "month": return isChinese ? "每月" : "Monthly"
        case "opus": return "Opus"
        case "sonnet": return "Sonnet"
        case "extra": return isChinese ? "額外用量" : "Extra usage"
        default: return window.label
        }
    }

    static func left(_ percent: Double) -> String {
        let value = Int(percent.rounded())
        return isChinese ? "剩餘 \(value)%" : "\(value)% left"
    }

    static func used(_ percent: Double) -> String {
        let value = Int(percent.rounded())
        return isChinese ? "已使用 \(value)%" : "\(value)% used"
    }

    static func reset(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate(isChinese ? "M月d日 HH:mm" : "MMM d HH:mm")
        return (isChinese ? "重設 " : "resets ") + formatter.string(from: date)
    }

    static func accountCount(_ count: Int) -> String {
        if isChinese { return "\(count) 個帳號" }
        return count == 1 ? "1 account" : "\(count) accounts"
    }

    static func resetDetail(_ date: Date, now: Date) -> String {
        guard date > now else { return isChinese ? "即將重設" : "resetting now" }
        let absolute = absoluteReset(date, now: now)
        let relative = duration(date.timeIntervalSince(now))
        return isChinese ? "\(absolute) 重設 · \(relative)後" : "resets \(absolute) · in \(relative)"
    }

    static func absoluteReset(_ date: Date, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if Calendar.current.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.setLocalizedDateFormatFromTemplate(isChinese ? "M月d日 HH:mm" : "MMM d HH:mm")
        }
        return formatter.string(from: date)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 {
            return isChinese ? "\(days) 天 \(hours) 小時" : "\(days)d \(hours)h"
        }
        if hours > 0 {
            return isChinese ? "\(hours) 小時 \(minutes) 分" : "\(hours)h \(minutes)m"
        }
        let value = max(1, minutes)
        return isChinese ? "\(value) 分" : "\(value)m"
    }

    static func updated(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func stale() -> String {
        isChinese ? "資料過舊" : "Stale"
    }

    static func live() -> String {
        isChinese ? "正常" : "Live"
    }

    static func needsSignIn() -> String {
        isChinese ? "請重新登入" : "Sign in again"
    }

    static func unavailable() -> String {
        isChinese ? "無法取得" : "Unavailable"
    }

    static func noData() -> String {
        isChinese ? "沒有資料" : "No data yet"
    }

    static func openHelper() -> String {
        isChinese ? "開啟 Usage Widget 選單" : "Open Usage Widget menu"
    }
}
