import SwiftUI

enum Theme {
    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let background = dynamic(dark: UIColor(red: 0.047, green: 0.051, blue: 0.059, alpha: 1), light: UIColor(red: 0.953, green: 0.949, blue: 0.937, alpha: 1))
    static let card = dynamic(dark: UIColor(red: 0.094, green: 0.102, blue: 0.118, alpha: 1), light: .white)
    /// Slightly lifted surface for things that sit on a card, such as chart tracks.
    static let raised = dynamic(dark: UIColor(red: 0.141, green: 0.153, blue: 0.176, alpha: 1), light: UIColor(red: 0.925, green: 0.922, blue: 0.91, alpha: 1))
    static let hairline = dynamic(dark: UIColor(white: 1, alpha: 0.07), light: UIColor(white: 0, alpha: 0.07))
    static let accent = Color(red: 0.80, green: 1.00, blue: 0.20)
    static let food = Color.orange
    static let water = Color.cyan
    static let steps = Color.green
    static let sleep = Color.indigo
    static let protein = Color.pink
    static let carbs = Color.yellow
    static let fat = Color.purple
    static let secondaryText = Color.primary.opacity(0.62)
    static let good = Color(red: 0.35, green: 0.85, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let low = Color(red: 1.0, green: 0.45, blue: 0.40)
}

/// Flat app background. Kept under its old name so every screen picks it up.
struct GlassBackdrop: View {
    var body: some View { Theme.background.ignoresSafeArea() }
}

extension View {
    /// Solid surface with a hairline edge and a soft drop. Name kept so every screen picks it up.
    func glass(_ radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self.background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glass(22)
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

/// One macro line: colored name, eaten / goal, thin bar. Goal shows only when the plan has one.
struct MacroRow: View {
    let name: String
    let eaten: Double
    let goal: Double
    var tint: Color = Theme.accent
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(name).foregroundStyle(tint).fontWeight(.semibold)
                Spacer()
                Text(goal > 0 ? "\(Int(eaten.rounded())) / \(Int(goal.rounded())) g" : "\(Int(eaten.rounded())) g").monospacedDigit()
            }.font(.subheadline)
            if goal > 0 { ProgressBar(fraction: eaten / goal, tint: tint).frame(height: 6) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Health-style section label above a group of cards.
struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.title3.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }
}

/// Ring for a daily goal. No goal means no ring, only the icon.
struct ProgressRing: View {
    var fraction: Double
    var tint: Color
    var icon: String
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: 5)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            Image(systemName: icon).font(.footnote.weight(.bold)).foregroundStyle(tint)
        }
        .frame(width: 38, height: 38)
        .animation(.easeOut(duration: 0.5), value: fraction)
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


/// Open arc gauge, 270 degrees. Value sits inside. Animates from the live value when it changes.
struct ArcGauge: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 14
    private let span = 0.75
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: span).stroke(Theme.raised, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle().trim(from: 0, to: span * min(1, max(0.001, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .rotationEffect(.degrees(135))
        .animation(.spring(duration: 0.6, bounce: 0), value: fraction)
    }
}

/// Thin labelled bar used for the parts of a score. Tint carries the status, the number carries the detail.
struct ComponentBar: View {
    var title: String
    var fraction: Double
    var detail: String
    var tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.footnote.weight(.semibold))
                Spacer()
                Text(detail).font(.caption).foregroundStyle(Theme.secondaryText).monospacedDigit()
            }
            ProgressBar(fraction: fraction, tint: tint).frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Stacked macro split for the day: how the calories eaten divide into protein, carbs and fat.
struct MacroSplit: View {
    var protein: Double, carbs: Double, fat: Double
    var body: some View {
        let kcal = [protein * 4, carbs * 4, fat * 9]
        let total = max(kcal.reduce(0, +), 1)
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(Array(zip(kcal, [Theme.protein, Theme.carbs, Theme.fat]).enumerated()), id: \.offset) { _, pair in
                    Capsule().fill(pair.1).frame(width: max(4, (geo.size.width - 6) * pair.0 / total))
                }
            }
        }
        .frame(height: 10)
        .opacity(kcal.reduce(0, +) > 0 ? 1 : 0.25)
    }
}
