import SwiftUI

// Wiederverwendbare „Mischpult"-Bausteine: Graphit-Panels, versenkte Regler,
// physische Schalter, Keycaps — ruhig, wertig, mit Klartext.

private extension Color {
    static let panelTop = Color(red: 0.20, green: 0.20, blue: 0.225)
    static let panelBot = Color(red: 0.145, green: 0.145, blue: 0.165)
    static let inset = Color(red: 0.09, green: 0.09, blue: 0.105)
    static let raiseTop = Color(red: 0.30, green: 0.30, blue: 0.33)
    static let raiseBot = Color(red: 0.23, green: 0.23, blue: 0.255)
    static let ink = Color(white: 0.93)
    static let inkMuted = Color(white: 0.62)
    static let inkFaint = Color(white: 0.48)
}

/// Ein Graphit-Panel (Karte), das zusammengehörige Einstellungen bündelt.
struct ConsolePanel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.inkFaint)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.panelTop, .panelBot], startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    // feiner Lichtsaum oben
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(height: 18).padding(.horizontal, 1).padding(.top, 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        }
    }
}

/// Eine Zeile im Panel: Titel + optionaler Hilfetext links, Bedienelement rechts.
struct FieldRow<Trailing: View>: View {
    let title: String
    var help: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                if let help {
                    Text(help).font(.system(size: 11)).foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

struct ConsoleDivider: View {
    var body: some View {
        Rectangle().fill(Color.black.opacity(0.4)).frame(height: 1)
            .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1).offset(y: 1))
            .padding(.horizontal, 16)
    }
}

/// Versenkter Segment-Umschalter mit erhabenem aktivem Feld.
struct ConsoleSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { value, label in
                let active = selection == value
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? Color.ink : Color.inkMuted)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(active ? LinearGradient(colors: [.raiseTop, .raiseBot], startPoint: .top, endPoint: .bottom)
                                         : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom))
                    )
                    .shadow(color: active ? .black.opacity(0.4) : .clear, radius: 3, y: 1)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = value }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.inset))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.black.opacity(0.5)))
    }
}

/// Physischer Kippschalter (aus = versenkt dunkel, an = Signalfarbe).
struct ConsoleToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Capsule()
            .fill(on ? Color.shoutLive : Color.inset)
            .frame(width: 46, height: 27)
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.4)))
            .overlay(
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.80)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 21, height: 21)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: on ? 9.5 : -9.5)
            )
            .animation(.easeOut(duration: 0.16), value: on)
            .onTapGesture { configuration.isOn.toggle() }
    }
}

/// Monospace-Tastenkappe (z. B. für den Hotkey).
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.inset))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.black.opacity(0.5)))
    }
}

/// Erhabener Konsolen-Knopf.
struct ConsoleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [.raiseTop, .raiseBot], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
