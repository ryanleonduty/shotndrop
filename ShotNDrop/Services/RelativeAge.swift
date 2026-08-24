import Foundation

/// Session-only age formatter. `RelativeDateTimeFormatter` cannot cap at
/// hours natively, so we roll our own with rounded integer buckets.
///   `< 60 s`  → `"just now"`
///   `< 60 m`  → `"Nm ago"`
///   `< 24 h`  → `"Nh ago"`
///   `≥ 24 h`  → `"24h+ ago"`
public enum RelativeAge {
    public static func format(interval: TimeInterval) -> String {
        let seconds = max(0, interval)
        if seconds < 60 { return "just now" }
        if seconds < 60 * 60 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        }
        if seconds < 24 * 60 * 60 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        }
        return "24h+ ago"
    }

    public static func format(from capturedAt: Date, to now: Date = Date()) -> String {
        format(interval: now.timeIntervalSince(capturedAt))
    }
}
