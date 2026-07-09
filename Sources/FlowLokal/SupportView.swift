import SwiftUI
import AppKit

/// „Unterstützen" — shout. ist ein Open-Source-Projekt. Keine Lizenz, kein Kauf:
/// Wer mag, kann die Weiterentwicklung freiwillig unterstützen.
struct SupportView: View {

    private let donateURL = "https://ko-fi.com/lilolama"
    private let githubURL = "https://github.com/LiLoLama/shout"

    private let points = [
        ("lock.open.fill", "Frei & quelloffen", "Der komplette Quellcode ist öffentlich — nutzen, anpassen, weitergeben."),
        ("lock.fill", "Lokal & privat", "Keine Cloud, keine Konten, keine Datenweitergabe. Alles bleibt auf deinem Mac."),
        ("arrow.triangle.branch", "Aktiv gepflegt", "Ich bemühe mich, shout. aktuell zu halten, zu verbessern und zu erweitern."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Unterstützen").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))

                ConsolePanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill").font(.system(size: 30)).foregroundStyle(Color.shoutLive)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("shout. ist Open Source").font(.system(size: 19, weight: .semibold)).foregroundStyle(Color(white: 0.95))
                                Text("Kostenlos, quelloffen und komplett lokal.").font(.system(size: 12)).foregroundStyle(Color(white: 0.58))
                            }
                            Spacer()
                        }

                        Text("Ich entwickle shout. in meiner freien Zeit und bemühe mich, die App aktuell zu halten, zu verbessern und zu erweitern. Wenn dir shout. hilft und du die Weiterentwicklung unterstützen möchtest, freue ich mich riesig — freiwillig, ohne Verpflichtung.")
                            .font(.system(size: 13)).foregroundStyle(Color(white: 0.62))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)

                        HStack(spacing: 10) {
                            Button {
                                if let url = URL(string: donateURL) { NSWorkspace.shared.open(url) }
                            } label: {
                                Label("Unterstützen", systemImage: "cup.and.saucer.fill").fontWeight(.semibold)
                            }
                            .buttonStyle(DonateButtonStyle())

                            Button {
                                if let url = URL(string: githubURL) { NSWorkspace.shared.open(url) }
                            } label: {
                                Label("Quellcode auf GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            }
                            .buttonStyle(ConsoleButtonStyle())
                        }
                    }
                    .padding(16)
                }

                ConsolePanel(title: "Was shout. ausmacht") {
                    VStack(spacing: 0) {
                        ForEach(points.indices, id: \.self) { i in
                            let p = points[i]
                            HStack(spacing: 12) {
                                Image(systemName: p.0).font(.system(size: 14)).foregroundStyle(Color.shoutLive).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.1).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Color(white: 0.9))
                                    Text(p.2).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 15).padding(.vertical, 12)
                            if i < points.count - 1 { ConsoleDivider() }
                        }
                    }
                }

                Text("Fehler gefunden oder eine Idee? Auf GitHub freue ich mich über Issues und Pull Requests.")
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
    }
}

/// Hervorgehobener Unterstützen-Knopf in der Signalfarbe.
private struct DonateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.shoutLive))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
