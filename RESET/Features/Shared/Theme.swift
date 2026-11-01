import SwiftUI

/// Design tokens read from the Figma file "RE:SET AI" (Today dark and light frames). The file defines no Figma
/// variables, so every value here is the hardcoded value in the frames.
enum Theme {
    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    // Surfaces
    static let background = dynamic(dark: hex(0x0C0D0F), light: hex(0xF3F2EF))
    static let card = dynamic(dark: hex(0x181A1E), light: .white)
    /// Track behind progress bars, and raised chips and secondary buttons.
    static let raised = dynamic(dark: hex(0x24272D), light: hex(0xE8E7E3))
    static let hairline = dynamic(dark: UIColor(white: 1, alpha: 0.07), light: UIColor(white: 0, alpha: 0.07))
    // Text
    static let text = dynamic(dark: .white, light: hex(0x0C0D0F))
    static let secondaryText = dynamic(dark: UIColor(white: 1, alpha: 0.62), light: hex(0x0C0D0F, 0.62))
    // Accent and metric colors
    static let accent = Color(uiColor: hex(0xCCFF33))
    /// Text and icons on top of the accent color.
    static let onAccent = Color(uiColor: hex(0x0C0D0F))
    static let food = Color(red: 1.00, green: 0.69, blue: 0.28)
    static let water = Color(uiColor: hex(0x5CC7FF))
    static let steps = accent
    static let sleep = Color(uiColor: hex(0xA391FF))
    static let protein = Color(uiColor: hex(0xFF7894))
    static let carbs = Color(uiColor: hex(0xF5D661))
    static let fat = Color(uiColor: hex(0x6BDBCC))
    static let good = Color(uiColor: hex(0x59D98C))
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let low = Color(red: 1.0, green: 0.45, blue: 0.40)

    // Shape and spacing
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 16
    static let tilePadding: CGFloat = 14
    static let screenInset: CGFloat = 20
    static let gap: CGFloat = 10
    static let barHeight: CGFloat = 6
    static let buttonHeight: CGFloat = 48

    /// Inter for text and Nunito Sans Bold for big numbers, as in the Figma file. Both are bundled in RESET/Fonts
    /// (SIL Open Font License) and registered through UIAppFonts. Sizes are fixed points like the frames, scaled
    /// with Dynamic Type through `relativeTo`.
    enum Face {
        case regular, semibold, bold
        var name: String { switch self { case .regular: "Inter-Regular"; case .semibold: "Inter-SemiBold"; case .bold: "Inter-Bold" } }
    }
    static func text(_ size: CGFloat, _ face: Face = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(face.name, size: size, relativeTo: style)
    }
    static func number(_ size: CGFloat, semibold: Bool = false, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(semibold ? "NunitoSans-SemiBold" : "NunitoSans-Bold", size: size, relativeTo: style)
    }

    /// Type scale in points, from the frames.
    enum Size {
        static let headline: CGFloat = 23
        static let bigNumber: CGFloat = 42
        static let stepNumber: CGFloat = 40
        static let timer: CGFloat = 44
        static let tileNumber: CGFloat = 29
        static let workNumber: CGFloat = 27
        static let cardTitle: CGFloat = 15
        static let body: CGFloat = 14
        static let tileTitle: CGFloat = 13
        static let caption: CGFloat = 12
        static let footnote: CGFloat = 11
        static let tab: CGFloat = 10
    }
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
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }
}

struct Card<Content: View>: View {
    var title: String?
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                Text(title).font(Theme.text(Theme.Size.body, .semibold)).foregroundStyle(Theme.secondaryText)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .glass(Theme.cardRadius)
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
                Capsule().fill(Theme.raised)
                Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: Theme.barHeight)
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


/// Calories and macros in one compact block. Shared by Today and Nutrition so both read the same.
struct FoodSummary: View {
    var kcal: Double
    var target: Double?
    var counting: Bool
    var protein: (eaten: Double, goal: Double)
    var carbs: (eaten: Double, goal: Double)
    var fat: (eaten: Double, goal: Double)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(alignment: .top) {
                CardHeading(icon: "utensils", title: "Food", tint: Theme.food)
                Spacer()
                if counting, let t = target {
                    Text("\(Int(kcal.rounded()).formatted()) of \(Int(t.rounded()).formatted()) kcal")
                        .font(Theme.text(Theme.Size.caption)).foregroundStyle(Theme.secondaryText).monospacedDigit()
                }
            }
            if counting {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let t = target {
                        let left = t - kcal
                        Text("\(Int(abs(left).rounded()))").font(Theme.number(Theme.Size.bigNumber)).tracking(-0.8)
                            .foregroundStyle(left >= 0 ? Theme.text : Theme.warn)
                        Text(left >= 0 ? "kcal left" : "kcal over").font(Theme.text(Theme.Size.body)).foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("\(Int(kcal.rounded()))").font(Theme.number(Theme.Size.bigNumber)).tracking(-0.8).foregroundStyle(Theme.text)
                        Text("kcal").font(Theme.text(Theme.Size.body)).foregroundStyle(Theme.secondaryText)
                    }
                }
            } else {
                Text("\(Int(protein.eaten.rounded())) g protein").font(Theme.number(32)).foregroundStyle(Theme.text)
            }
            HStack(spacing: 12) {
                macro("Protein", protein, Theme.protein)
                macro("Carbs", carbs, Theme.carbs)
                macro("Fat", fat, Theme.fat)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func macro(_ name: String, _ m: (eaten: Double, goal: Double), _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(Theme.text(Theme.Size.caption)).foregroundStyle(Theme.secondaryText)
            Text(m.goal > 0 ? "\(Int(m.eaten.rounded())) / \(Int(m.goal.rounded())) g" : "\(Int(m.eaten.rounded())) g")
                .font(Theme.text(Theme.Size.caption, .semibold)).foregroundStyle(Theme.text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            ProgressBar(fraction: m.goal > 0 ? m.eaten / m.goal : 0, tint: tint).opacity(m.goal > 0 ? 1 : 0.3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One quiet list group. Rows sit inside a single surface, separated by hairlines. Replaces a stack of separate cards.
struct ListGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(Theme.cardRadius)
    }
}

/// Row for a `ListGroup`: icon, title, optional trailing value, chevron.
struct GroupRow: View {
    var title: String
    var icon: String
    var value: String?
    var tint: Color = Theme.secondaryText
    var showChevron = true
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body.weight(.medium)).foregroundStyle(tint).frame(width: 24)
            Text(title).font(.body)
            Spacer()
            if let value { Text(value).font(.subheadline).foregroundStyle(Theme.secondaryText).monospacedDigit() }
            if showChevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText.opacity(0.6)) }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct GroupDivider: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 52) }
}

/// Screen title row from the Figma "Page navigation": calendar icon, 20pt title, 11pt date, optional trailing control. 56 high.
struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Icon("calendar-days", size: 22).foregroundStyle(Theme.text).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.text(20, .bold, relativeTo: .title3)).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.text(Theme.Size.footnote)).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            trailing
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}
