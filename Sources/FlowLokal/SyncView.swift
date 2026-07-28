import SwiftUI

/// „Sync & Geräte" — bewusst ohne Cloud: Daten als Datei exportieren, auf ein
/// anderes Gerät kopieren und dort importieren.
struct SyncView: View {
    let onExport: () -> String
    let onImport: () -> String

    @State private var status = ""

    private var contents: [(String, String, String)] {
        [
            ("text.book.closed.fill", Loc.t("Wörterbuch"), Loc.t("Begriffe & gelernte Korrekturen")),
            ("clock.arrow.circlepath", Loc.t("Verlauf"), Loc.t("Deine bisherigen Diktate")),
            ("chart.bar.xaxis", Loc.t("Statistiken"), Loc.t("Wörter, Streak, aktive Tage")),
            ("slider.horizontal.3", Loc.t("Einstellungen"), Loc.t("Aufnahme-Art, Hotkey, Mikrofon, Formatierung")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(Loc.t("Sync & Geräte")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))

                ConsolePanel(title: Loc.t("Daten übertragen")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Loc.t("shout. speichert alles lokal — keine Cloud. Für ein zweites Gerät exportierst du eine Datei, kopierst sie hinüber (AirDrop, USB-Stick …) und importierst sie dort. Die Datei passt auch zur Windows- und iPhone-App."))
                            .font(.system(size: 13)).foregroundStyle(Color(white: 0.62))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button(Loc.t("Exportieren …")) { status = onExport() }.buttonStyle(ConsoleButtonStyle())
                            Button(Loc.t("Importieren …")) { status = onImport() }.buttonStyle(ConsoleButtonStyle())
                        }
                        if !status.isEmpty {
                            Text(status).font(.system(size: 12)).foregroundStyle(Color.shoutLive)
                        }
                    }
                    .padding(16)
                }

                ConsolePanel(title: Loc.t("In der Datei enthalten")) {
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

                Text(Loc.t("Beim Import werden die aktuellen Daten auf diesem Gerät ersetzt. Die Datei enthält deinen Verlauf im Klartext — behandle sie vertraulich."))
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
