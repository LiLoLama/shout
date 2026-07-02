import SwiftUI

/// „Sync & Geräte" — bewusst ohne Cloud: Daten als Datei exportieren, auf ein
/// anderes Gerät kopieren und dort importieren.
struct SyncView: View {
    let onExport: () -> String
    let onImport: () -> String

    @State private var status = ""

    private let contents = [
        ("text.book.closed.fill", "Wörterbuch", "Begriffe & gelernte Korrekturen"),
        ("clock.arrow.circlepath", "Verlauf", "Deine bisherigen Diktate"),
        ("chart.bar.xaxis", "Statistiken", "Wörter, Streak, aktive Tage"),
        ("slider.horizontal.3", "Einstellungen & Lizenz", "Modus, Hotkey, Mikrofon, Pro-Lizenz"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Sync & Geräte").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))

                ConsolePanel(title: "Daten übertragen") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("shout. speichert alles lokal — keine Cloud. Für ein zweites Gerät exportierst du eine Datei, kopierst sie hinüber (AirDrop, USB-Stick …) und importierst sie dort.")
                            .font(.system(size: 13)).foregroundStyle(Color(white: 0.62))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button("Exportieren …") { status = onExport() }.buttonStyle(ConsoleButtonStyle())
                            Button("Importieren …") { status = onImport() }.buttonStyle(ConsoleButtonStyle())
                        }
                        if !status.isEmpty {
                            Text(status).font(.system(size: 12)).foregroundStyle(Color.shoutLive)
                        }
                    }
                    .padding(16)
                }

                ConsolePanel(title: "In der Datei enthalten") {
                    VStack(spacing: 0) {
                        ForEach(contents.indices, id: \.self) { i in
                            let c = contents[i]
                            HStack(spacing: 12) {
                                Image(systemName: c.0).font(.system(size: 14)).foregroundStyle(Color.shoutLive).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.1).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Color(white: 0.9))
                                    Text(c.2).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 15).padding(.vertical, 12)
                            if i < contents.count - 1 { ConsoleDivider() }
                        }
                    }
                }

                Text("Beim Import werden die aktuellen Daten auf diesem Gerät ersetzt.")
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
    }
}
