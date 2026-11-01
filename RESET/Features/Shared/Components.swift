import SwiftUI

// The six shared components from the Figma file "RE:SET AI": Card, Tile, Pill button, Progress bar,
// Chat bubble and Tab bar. Sizes, colors and type come from `Theme`. Card and ProgressBar live in Theme.swift.

/// Lucide icon exported from Figma (Assets.xcassets/Icons). Template rendered, so it takes the foreground style.
/// A name with no exported icon falls back to the SF Symbol of that name, for icons the frames do not show.
struct Icon: View {
    var name: String
    var size: CGFloat
    init(_ name: String, size: CGFloat = 18) { self.name = name; self.size = size }
    var body: some View {
        Group {
            if UIImage(named: "ic-\(name)") != nil { Image("ic-\(name)").renderingMode(.template).resizable().scaledToFit() }
            else { Image(systemName: name).resizable().scaledToFit() }
        }
        .frame(width: size, height: size)
    }
}

/// Icon and title row at the top of a card. Icon takes the tint, title the text color.
struct CardHeading: View {
    var icon: String
    var title: String
    var tint: Color = Theme.accent
    var iconSize: CGFloat = 18
    var body: some View {
        HStack(spacing: 8) {
            Icon(icon, size: iconSize).foregroundStyle(tint)
            Text(title).font(Theme.text(Theme.Size.cardTitle, .semibold)).foregroundStyle(Theme.text)
        }
    }
}

/// Small metric tile: icon and name, one big number, a caption, a goal bar. Optional plus for one tap logging.
struct Tile: View {
    var title: String
    var icon: String
    var tint: Color
    var value: String
    var caption: String
    var fraction: Double?
    var plus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Icon(icon, size: 16).foregroundStyle(tint)
                    Text(title).font(Theme.text(Theme.Size.tileTitle)).foregroundStyle(Theme.text)
                }
                Spacer()
                if plus { Icon("circle-plus", size: 20).foregroundStyle(tint) }
            }
            Text(value).font(Theme.number(Theme.Size.tileNumber)).tracking(-0.8).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(Theme.text(Theme.Size.caption)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            ProgressBar(fraction: fraction ?? 0, tint: tint).opacity(fraction == nil ? 0.3 : 1)
        }
        .padding(Theme.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(Theme.cardRadius)
        .accessibilityElement(children: .combine)
    }
}

/// Full width capsule button, 48 high. Primary is lime, secondary is the raised surface.
struct PillButton: View {
    enum Kind { case primary, secondary }
    var title: String
    var icon: String?
    var kind: Kind = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, size: 18) }
                Text(title).font(Theme.text(Theme.Size.cardTitle, .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
        }
        .buttonStyle(Press())
        .background(kind == .primary ? Theme.accent : Theme.raised, in: Capsule())
        .foregroundStyle(kind == .primary ? Theme.onAccent : Theme.text)
    }
}

/// One chat message. The assistant bubble is a bordered card with a small label. Yours is lime.
struct ChatBubble: View {
    var text: String
    var mine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !mine { Text("RE:SET AI").font(Theme.text(Theme.Size.footnote, .semibold)).foregroundStyle(Theme.secondaryText) }
            Text(text).font(Theme.text(Theme.Size.cardTitle)).textSelection(.enabled)
        }
        .padding(16)
        .background(mine ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { if !mine { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline) } }
        .foregroundStyle(mine ? Theme.onAccent : Theme.text)
    }
}

/// Styles the system tab bar to the Figma tab bar: dark surface, hairline on top, 10pt labels,
/// selected tab in lime and semibold. The icons are 21 pt template images.
enum TabBarStyle {
    static func apply() {
        let normal = UIColor(Theme.secondaryText), selected = UIColor(Theme.accent)
        let regular = UIFont(name: "Inter-Regular", size: Theme.Size.tab) ?? .systemFont(ofSize: Theme.Size.tab)
        let semibold = UIFont(name: "Inter-SemiBold", size: Theme.Size.tab) ?? .systemFont(ofSize: Theme.Size.tab, weight: .semibold)
        let item = UITabBarItemAppearance(style: .stacked)
        item.normal.iconColor = normal
        item.normal.titleTextAttributes = [.font: regular, .foregroundColor: normal]
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.font: semibold, .foregroundColor: selected]
        let look = UITabBarAppearance()
        look.configureWithOpaqueBackground()
        look.backgroundColor = UIColor(Theme.background)
        look.shadowColor = UIColor(Theme.hairline)
        look.stackedLayoutAppearance = item
        look.inlineLayoutAppearance = item
        look.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = look
        UITabBar.appearance().scrollEdgeAppearance = look
    }
}

#Preview("Components") {
    ScrollView {
        VStack(spacing: 12) {
            Card {
                CardHeading(icon: "person-standing", title: "A little air after work", iconSize: 20)
                Text("A gentle 15-minute walk can help you switch off. Only if you feel up to it.")
                    .font(Theme.text(Theme.Size.body)).foregroundStyle(Theme.secondaryText)
                HStack(spacing: 10) {
                    PillButton(title: "Start walk") {}
                    PillButton(title: "Can\u{2019}t today", kind: .secondary) {}
                }
            }
            HStack(spacing: 12) {
                Tile(title: "Water", icon: "droplet", tint: Theme.water, value: "1.2 L", caption: "of 3.0 L  \u{b7}  +250 ml", fraction: 0.4, plus: true)
                Tile(title: "Sleep", icon: "moon", tint: Theme.sleep, value: "7.4 h", caption: "of 8 h", fraction: 0.925)
            }
            PillButton(title: "Log food or drink", icon: "plus") {}
            ProgressBar(fraction: 0.75)
            ChatBubble(text: "Start winding down at 22:30. Give yourself a quiet landing before bed.")
            ChatBubble(text: "I\u{2019}m exhausted after work.", mine: true)
        }
        .padding(20)
    }
    .background(Theme.background)
}
