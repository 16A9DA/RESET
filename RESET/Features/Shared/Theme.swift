import SwiftUI

enum Theme {
    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let background = dynamic(dark: UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1), light: UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
    static let card = dynamic(dark: UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1), light: .white)
    static let accent = Color(red: 0.80, green: 1.00, blue: 0.20)
    static let secondaryText = Color.primary.opacity(0.62)
    static let good = Color(red: 0.35, green: 0.85, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let low = Color(red: 1.0, green: 0.45, blue: 0.40)
}

/// Soft colour behind the glass so it has something to refract.
struct GlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.background
            Circle().fill(Theme.accent.opacity(scheme == .dark ? 0.22 : 0.35)).frame(width: 320).blur(radius: 90).offset(x: -130, y: -260)
            Circle().fill(Color(red: 0.25, green: 0.45, blue: 1).opacity(scheme == .dark ? 0.28 : 0.2)).frame(width: 360).blur(radius: 100).offset(x: 160, y: 120)
            Circle().fill(Color(red: 0.7, green: 0.3, blue: 1).opacity(scheme == .dark ? 0.18 : 0.12)).frame(width: 280).blur(radius: 90).offset(x: -120, y: 380)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Liquid Glass on iOS 26 and later, a frosted material before that.
    @ViewBuilder func glass(_ radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape).overlay(shape.strokeBorder(Color.white.opacity(0.15)))
        }
    }
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
        .glass(20)
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
                Capsule().fill(Color.primary.opacity(0.1))
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
