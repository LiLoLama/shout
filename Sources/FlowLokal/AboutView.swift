import AppKit
import SwiftUI

/// Zugriff auf den Sparkle-Updater, ohne dass die View Sparkle importieren muss.
/// Der AppDelegate füllt die Closures mit dem echten SPUUpdater.
struct UpdateBridge {
    var check: () -> Void = {}
    var lastCheck: () -> Date? = { nil }
    var automatic: () -> Bool = { true }
    var setAutomatic: (Bool) -> Void = { _ in }

    /// Fallback für Vorschauen/Tests: tut nichts.
    static let disabled = UpdateBridge()
}

/// „Über shout." — hängt am Klick auf die Wortmarke in der Seitenleiste.
/// Zeigt Version und Build, sucht nach Aktualisierungen und verlinkt Projekt,
/// Lizenz und Unterstützen. Bewusst kompakt als Popover statt eigenem Fenster.
struct AboutView: View {
    var updates: UpdateBridge = .disabled

    @State private var copied = false
    @State private var autoCheck = true
    @State private var lastCheck: Date?

    private static let githubURL = "https://github.com/LiLoLama/shout"
    private static let donateURL = "https://ko-fi.com/lilolama"

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            updateSection
            divider
            links
            Text(Loc.t("Alles lokal — Sprache, Text und Verlauf verlassen deinen Mac nicht."))
                .font(.system(size: 10.5)).foregroundStyle(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 16)
        }
        .frame(width: 320)
        .background(Color.shoutSidebar)
        .preferredColorScheme(.dark)
        .onAppear {
            autoCheck = updates.automatic()
            lastCheck = updates.lastCheck()
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .top, spacing: 13) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable().frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text("shout").font(.system(size: 20, weight: .bold))
                    Text(".").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.shoutLive)
                }
                .foregroundStyle(Color(white: 0.95))
                Text(Loc.t("Lokale Diktier-App für macOS"))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("shout. \(version) (\(build))", forType: .string)
                    copied = true
                } label: {
                    Text(copied ? Loc.t("Kopiert") : Loc.f("Version %@ (Build %@)", version, build))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(copied ? Color.shoutLive : Color(white: 0.7))
                }
                .buttonStyle(.plain)
                .help(Loc.t("Version kopieren"))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 16)
    }

    // MARK: - Aktualisierung

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Loc.t("Aktualisierung").uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(Color(white: 0.45))

            Text(lastCheck.map { Loc.f("Zuletzt geprüft: %@", Self.stamp.string(from: $0)) }
                 ?? Loc.t("Noch nicht nach Aktualisierungen gesucht."))
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.6))
                .fixedSize(horizontal: false, vertical: true)

            Button(Loc.t("Nach Aktualisierungen suchen")) {
                updates.check()
                // Sparkle setzt das Datum asynchron — kurz später nachziehen.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    lastCheck = updates.lastCheck()
                }
            }
            .buttonStyle(ConsoleButtonStyle())

            Toggle(isOn: Binding(get: { autoCheck },
                                 set: { autoCheck = $0; updates.setAutomatic($0) })) {
                Text(Loc.t("Automatisch nach Aktualisierungen suchen"))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.6))
            }
            .toggleStyle(.checkbox).tint(Color.shoutLive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    // MARK: - Verweise

    private var links: some View {
        VStack(spacing: 0) {
            linkRow(Loc.t("Quellcode auf GitHub"), "chevron.left.forwardslash.chevron.right", Self.githubURL)
            linkRow(Loc.t("Fehler melden"), "ladybug.fill", Self.githubURL + "/issues")
            linkRow(Loc.t("Lizenz (GPL-3.0)"), "doc.text", Self.githubURL + "/blob/main/LICENSE")
            linkRow(Loc.t("Unterstützen …"), "cup.and.saucer.fill", Self.donateURL)
        }
        .padding(.vertical, 6)
    }

    private func linkRow(_ title: String, _ icon: String, _ url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 16)
                    .foregroundStyle(Color.shoutLive)
                Text(title).font(.system(size: 12)).foregroundStyle(Color(white: 0.85))
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.4))
            }
            .padding(.horizontal, 18).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
