import SwiftUI

// Flache, clean-e Bausteine (an Wispr Flow angelehnt): dezente Karten, keine
// Verläufe/Innenschatten, viel Ruhe — Akzent nur über die Signalfarbe.

private extension Color {
    static let card = Color(white: 0.165)
    static let cardBorder = Color.white.opacity(0.07)
    static let track = Color(white: 0.11)
    static let segActive = Color(white: 0.27)
    static let ink = Color(white: 0.94)
    static let inkMuted = Color(white: 0.60)
    static let inkFaint = Color(white: 0.45)
}

/// Flache Karte, die zusammengehörige Einstellungen bündelt.
struct ConsolePanel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Color.inkFaint)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.cardBorder))
        }
    }
}

/// Eine Zeile: Titel + optionaler Hilfetext links, Bedienelement rechts.
struct FieldRow<Trailing: View>: View {
    let title: String
    var help: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Color.ink)
                if let help {
                    Text(help).font(.system(size: 11)).foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }
}

struct ConsoleDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.horizontal, 15)
    }
}

/// Flacher Segment-Umschalter (aktives Feld: dezent heller, kein 3D).
struct ConsoleSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                let active = selection == value
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(active ? Color.ink : Color.inkMuted)
                    .padding(.horizontal, 13).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(active ? Color.segActive : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = value }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.track))
    }
}

/// Monospace-Tastenkappe — flach.
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.track))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.06)))
    }
}

/// Flacher Knopf.
struct ConsoleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.22)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.08)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
