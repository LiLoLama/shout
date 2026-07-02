import SwiftUI

/// Konto & Lizenz — Plan anzeigen, shout. Pro per Lizenzschlüssel freischalten.
struct LicenseView: View {
    @ObservedObject var license: LicenseStore

    @State private var keyInput = ""
    @State private var showError = false

    private let benefits = [
        ("arrow.triangle.2.circlepath", "Sync & Geräte", "Wörterbuch & Einstellungen zwischen deinen Macs abgleichen."),
        ("globe", "Weitere Sprachen", "Diktieren in zusätzlichen Sprachen."),
        ("person.2.fill", "Team", "Lizenzen und geteilte Wörterbücher fürs Team."),
        ("bolt.fill", "Priorität", "Früher Zugriff auf neue Funktionen."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Konto & Lizenz").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))

                ConsolePanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: license.isPro ? "checkmark.seal.fill" : "seal")
                                .font(.system(size: 30))
                                .foregroundStyle(license.isPro ? Color.shoutLive : Color(white: 0.45))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(license.isPro ? "shout. Pro" : "shout. Free")
                                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(Color(white: 0.95))
                                Text(license.isPro ? "Lizenziert für \(license.licensedTo)" : "Grundfunktionen aktiv")
                                    .font(.system(size: 12)).foregroundStyle(Color(white: 0.58))
                            }
                            Spacer()
                            if license.isPro {
                                Button("Lizenz entfernen") { license.deactivate() }
                                    .buttonStyle(ConsoleButtonStyle())
                            }
                        }

                        if !license.isPro {
                            ConsoleDivider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Lizenzschlüssel eingeben").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.7))
                                HStack(spacing: 8) {
                                    TextField("shout. Pro Schlüssel …", text: $keyInput)
                                        .textFieldStyle(.plain).font(.system(size: 12.5, design: .monospaced))
                                        .foregroundStyle(Color(white: 0.92))
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.11)))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(showError ? Color.shoutLive : Color.white.opacity(0.07)))
                                        .onSubmit(activate)
                                    Button("Aktivieren", action: activate)
                                        .buttonStyle(ConsoleButtonStyle())
                                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                if showError {
                                    Text("Ungültiger Lizenzschlüssel.").font(.system(size: 11)).foregroundStyle(Color.shoutLive)
                                }
                            }
                        }
                    }
                    .padding(16)
                }

                ConsolePanel(title: license.isPro ? "In deinem Plan" : "shout. Pro schaltet frei") {
                    VStack(spacing: 0) {
                        ForEach(benefits.indices, id: \.self) { i in
                            let b = benefits[i]
                            HStack(spacing: 12) {
                                Image(systemName: b.0).font(.system(size: 14))
                                    .foregroundStyle(license.isPro ? Color.shoutLive : Color(white: 0.5))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.1).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Color(white: 0.9))
                                    Text(b.2).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                                }
                                Spacer()
                                if license.isPro {
                                    Text("Bald").font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.white.opacity(0.10))).foregroundStyle(Color(white: 0.5))
                                }
                            }
                            .padding(.horizontal, 15).padding(.vertical, 12)
                            if i < benefits.count - 1 { ConsoleDivider() }
                        }
                    }
                }

                Text("Alle Kernfunktionen (Diktat, Formatierung, Wörterbuch, Verlauf, Statistiken) sind bereits ohne Pro nutzbar. Pro schaltet künftige Zusatzfunktionen frei.")
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
    }

    private func activate() {
        showError = !license.activate(keyInput)
        if !showError { keyInput = "" }
    }
}
