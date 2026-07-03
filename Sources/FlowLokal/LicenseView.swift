import SwiftUI
import AppKit

/// Konto & Lizenz — Testphase-Status, Kauf (Einmalkauf) und Schlüssel-Aktivierung.
struct LicenseView: View {
    @ObservedObject var license: LicenseStore

    @State private var keyInput = ""
    @State private var showError = false

    // Kaufoptionen (anpassbar):
    private let price = "150 €"
    // Stripe Payment Link (im Stripe-Dashboard erstellen, siehe server/README.md).
    // Nach dem Kauf stellt der Webhook-Worker den Lizenzschlüssel per E-Mail zu.
    private let purchaseURL = "https://buy.stripe.com/DEIN_PAYMENT_LINK"

    private let features = [
        ("mic.fill", "Diktieren, überall", "Per Hotkey in jede App — komplett on-device."),
        ("wand.and.stars", "Automatisches Aufräumen", "Füllwörter raus, Interpunktion, Listen."),
        ("text.book.closed.fill", "Lernendes Wörterbuch", "Eigennamen & Korrekturen, auch automatisch."),
        ("clock.arrow.circlepath", "Verlauf & Statistiken", "Alles nachlesbar, inkl. Sprachprofil."),
        ("lock.fill", "Lokal & privat", "Kein Cloud, keine Konten, keine Datenweitergabe."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Konto & Lizenz").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))

                ConsolePanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: statusIcon).font(.system(size: 30)).foregroundStyle(statusColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(statusTitle).font(.system(size: 19, weight: .semibold)).foregroundStyle(Color(white: 0.95))
                                Text(statusSubtitle).font(.system(size: 12)).foregroundStyle(Color(white: 0.58))
                            }
                            Spacer()
                            if license.isLicensed {
                                Button("Lizenz entfernen") { license.deactivate() }.buttonStyle(ConsoleButtonStyle())
                            }
                        }

                        if !license.isLicensed {
                            ConsoleDivider()
                            HStack(spacing: 10) {
                                Button {
                                    if let url = URL(string: purchaseURL) { NSWorkspace.shared.open(url) }
                                } label: {
                                    Text("shout. kaufen — \(price)").fontWeight(.semibold)
                                }
                                .buttonStyle(BuyButtonStyle())
                                Text("Lifetime-Lizenz · kein Abo").font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Lizenzschlüssel eingeben").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.7))
                                HStack(spacing: 8) {
                                    TextField("Schlüssel aus der Kaufbestätigung …", text: $keyInput)
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

                ConsolePanel(title: "Enthalten") {
                    VStack(spacing: 0) {
                        ForEach(features.indices, id: \.self) { i in
                            let f = features[i]
                            HStack(spacing: 12) {
                                Image(systemName: f.0).font(.system(size: 14)).foregroundStyle(Color.shoutLive).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.1).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Color(white: 0.9))
                                    Text(f.2).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 15).padding(.vertical, 12)
                            if i < features.count - 1 { ConsoleDivider() }
                        }
                    }
                }

                Text("Lifetime-Lizenz für \(price) — einmal zahlen, für immer nutzen. Kein Abo, keine Folgekosten. Cloud-Diktier-Dienste kosten oft mehr pro Jahr. Alle Funktionen inklusive, alles läuft lokal auf deinem Mac.")
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Statusdarstellung

    private var statusIcon: String {
        if license.isLicensed { return "checkmark.seal.fill" }
        return license.isTrialActive ? "clock.badge.checkmark" : "lock.fill"
    }
    private var statusColor: Color {
        if license.isLicensed || license.isTrialActive { return Color.shoutLive }
        return Color(white: 0.5)
    }
    private var statusTitle: String {
        if license.isLicensed { return "shout. — Vollversion" }
        return license.isTrialActive ? "Testphase" : "Testphase abgelaufen"
    }
    private var statusSubtitle: String {
        if license.isLicensed { return "Lizenziert für \(license.licensedTo)" }
        if license.isTrialActive {
            let d = license.trialDaysRemaining
            return "Noch \(d) \(d == 1 ? "Tag" : "Tage") — voller Zugriff."
        }
        return "Kaufe shout., um weiter zu diktieren."
    }

    private func activate() {
        showError = !license.activate(keyInput)
        if !showError { keyInput = "" }
    }
}

/// Hervorgehobener Kauf-Knopf in der Signalfarbe.
private struct BuyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.shoutLive))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
