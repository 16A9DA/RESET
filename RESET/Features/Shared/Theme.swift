import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let accent = Color(red: 0.80, green: 1.00, blue: 0.20)
    static let secondaryText = Color.white.opacity(0.62)
    static let good = Color(red: 0.35, green: 0.85, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let low = Color(red: 1.0, green: 0.45, blue: 0.40)
}

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.secondaryText)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct BigMetric: View {
    var value: String
    var unit: String = ""
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.subheadline).foregroundStyle(Theme.secondaryText) }
            }
            if let caption { Text(caption).font(.footnote).foregroundStyle(Theme.secondaryText) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Honest empty state: say what is missing and how to fix it.
struct EmptyNote: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(Theme.secondaryText)
            Text(title).font(.headline)
            Text(message).font(.footnote).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct ProgressBar: View {
    var fraction: Double
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

extension Binding where Value == Int {
    /// Minutes after midnight as a Date, for DatePicker.
    func asTimeOfDay() -> Binding<Date> {
        Binding<Date>(
            get: { Calendar.current.date(bySettingHour: wrappedValue / 60, minute: wrappedValue % 60, second: 0, of: .now) ?? .now },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

enum Fmt {
    static func kcal(_ v: Double?) -> String { v.map { String(Int($0.rounded())) } ?? "Estimate unavailable" }
    static func clock(minutes: Int) -> String {
        let d = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return d.formatted(date: .omitted, time: .shortened)
    }
    static func hours(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        return "\(m / 60)h \(m % 60)m"
    }
}
