import SwiftUI

/// Das Fenster „Neu in shout.“: je Eintrag eine Seite (neueste zuerst) mit
/// Erklär-Animation, darunter der Text. „Überspringen“ und „Fertig“ rufen
/// `onClose`; der Aufrufer sorgt dafür, dass das nur einmal wirkt.
struct WhatsNewView: View {
    let entries: [ChangelogEntry]
    let keys: [String]
    let onClose: () -> Void

    @State private var page = 0
    /// Erst nach ~1 s gilt ⏎ als „Weiter“/„Fertig“: Ein ⏎, das noch dem Tippen vor dem
    /// Erscheinen des Fensters gehört, soll es nicht gleich schließen. Klicken geht immer.
    @State private var enterArmed = false

    init(entries: [ChangelogEntry], keys: [String], onClose: @escaping () -> Void) {
        self.entries = entries
        self.keys = keys
        self.onClose = onClose
    }

    private var isLast: Bool { page >= entries.count - 1 }

    /// Mindestgröße des (in der Größe veränderbaren) Fensters.
    static let minSize = CGSize(width: 720, height: 620)
    /// Anteil der Fensterhöhe, den die Animation höchstens einnimmt; der Rest gehört dem Text.
    private static let maxStageShare: CGFloat = 0.58

    var body: some View {
        GeometryReader { geo in
            content(maxStageHeight: geo.size.height * Self.maxStageShare)
        }
        .frame(minWidth: Self.minSize.width, minHeight: Self.minSize.height)
        .background(Color.shoutWindow)
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            enterArmed = true
        }
    }

    private func content(maxStageHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            if entries.indices.contains(page) {
                // `.id`: Jede Seite bekommt eine eigene Ansicht und damit einen
                // neuen Controller; der alte hält beim Verschwinden an.
                WhatsNewPage(entry: entries[page], keys: keys, maxStageHeight: maxStageHeight)
                    .id(entries[page].id)
            } else {
                Spacer()
            }
            HStack {
                Button(Loc.t("Überspringen"), action: onClose)
                    .buttonStyle(ConsoleButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if isLast {
                    Button(Loc.t("Fertig"), action: onClose)
                        .buttonStyle(ConsoleButtonStyle())
                        .keyboardShortcut(enterArmed ? .defaultAction : nil)
                } else {
                    Button(Loc.t("Weiter")) { page += 1 }
                        .buttonStyle(ConsoleButtonStyle())
                        .keyboardShortcut(enterArmed ? .defaultAction : nil)
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 20)
    }
}

/// Eine Seite: Kopf, Animation (wenn es sie gibt) in voller Inhaltsbreite, Text darunter.
private struct WhatsNewPage: View {
    let entry: ChangelogEntry
    let keys: [String]
    /// Höchste Höhe der Bühne (ohne Leiste); ist sie kleiner als Breite ÷ 1,6,
    /// schrumpft die Animation samt Leiste entsprechend und bleibt mittig.
    let maxStageHeight: CGFloat
    /// Entsteht erst beim Erscheinen — nicht im `init`, das SwiftUI oft mehrfach aufruft.
    @State private var controller: ExplainerController?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Loc.f("Neu in shout. %@", entry.version.description))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(white: 0.95))
            if let controller {
                ExplainerView(controller: controller, maxStageHeight: maxStageHeight)
                    .frame(maxWidth: .infinity)
            }
            ScrollView {
                ChangelogText(entry.text(german: Loc.isGerman))
                    .padding(.trailing, 6)
            }
        }
        .onAppear {
            if controller == nil, let name = entry.video, ExplainerController.url(for: name) != nil {
                controller = ExplainerController(name: name, german: Loc.isGerman, keys: keys, autoplay: true)
            }
        }
        .onDisappear { controller?.stop() }
    }
}
