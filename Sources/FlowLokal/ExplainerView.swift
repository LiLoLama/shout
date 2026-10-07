import SwiftUI
import WebKit

/// Spielt eine mitgelieferte Erklär-Animation (`Explainers/<name>.html`) im
/// `WKWebView` ab. Die Seite steuert sich über `window.explainer`; die Leiste
/// darunter ist nativ. Kein Netz: geladen wird nur aus dem Explainers-Ordner.
@MainActor
final class ExplainerController: NSObject, ObservableObject {

    @Published private(set) var isPlaying = false
    /// Die Animation startet stumm — Ton schaltet man bewusst ein.
    @Published private(set) var isMuted = true
    @Published private(set) var ended = false
    /// Die Seite ließ sich nicht laden; die Ansicht blendet den Player dann aus.
    @Published private(set) var failed = false

    let webView: WKWebView
    private let folder: URL
    private let userContent: WKUserContentController
    private var handlerInstalled = false

    /// `Explainers/<name>.html` im Bundle, `nil` wenn die Datei fehlt.
    static func url(for name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "html", subdirectory: "Explainers")
    }

    /// - Parameters:
    ///   - keys: Anzeige der Scratchpad- und der Eingangs-Taste (leer = Vorgabe der Animation).
    init?(name: String, german: Bool, keys: [String], autoplay: Bool) {
        guard let url = Self.url(for: name) else { return nil }
        let folder = url.deletingLastPathComponent().standardizedFileURL
        self.folder = folder

        let content = WKUserContentController()
        userContent = content
        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        super.init()

        // Schwacher Proxy: `userContentController` hält den Handler fest, der
        // Controller soll davon nicht am Leben bleiben.
        content.add(ExplainerMessageProxy(target: self), name: "explainer")
        handlerInstalled = true
        webView.navigationDelegate = self

        // „Bewegung reduzieren“: nicht von selbst losspielen.
        let reduziert = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var teile = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        teile.queryItems = [
            URLQueryItem(name: "lang", value: german ? "de" : "en"),
            URLQueryItem(name: "muted", value: "1"),
            URLQueryItem(name: "autoplay", value: autoplay && !reduziert ? "1" : "0"),
            URLQueryItem(name: "keys", value: keys.prefix(2).joined(separator: ",")),
        ]
        guard let ziel = teile.url else { return nil }
        webView.loadFileURL(ziel, allowingReadAccessTo: folder)
    }

    // MARK: - Bedienung

    func togglePlay() { run(isPlaying ? "pause()" : "play()") }

    func restart() { run("restart()") }

    func toggleMute() {
        isMuted.toggle()
        run("setMuted(\(isMuted ? "true" : "false"))")
    }

    /// Hält die Animation an und löst den Handler — wenn die Ansicht verschwindet.
    func stop() {
        run("pause()")
        removeHandler()
    }

    private func run(_ call: String) {
        webView.evaluateJavaScript("window.explainer.\(call)", completionHandler: nil)
    }

    private func removeHandler() {
        guard handlerInstalled else { return }
        userContent.removeScriptMessageHandler(forName: "explainer")
        handlerInstalled = false
    }

    // MARK: - Meldungen der Seite

    fileprivate func receive(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "state":
            if let spielt = dict["playing"] as? Bool {
                isPlaying = spielt
                if spielt { ended = false }
            }
            if let stumm = dict["muted"] as? Bool { isMuted = stumm }
        case "ended":
            isPlaying = false
            ended = true
        default:
            break
        }
    }
}

/// Reicht die Meldungen schwach an den Controller weiter.
private final class ExplainerMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var target: ExplainerController?

    init(target: ExplainerController) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { target?.receive(body) }
    }
}

extension ExplainerController: WKNavigationDelegate {

    /// Nur Dateien aus dem Explainers-Ordner; alles andere (Links, Netz) bleibt draußen.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.isFileURL else {
            decisionHandler(.cancel)
            return
        }
        let pfad = url.standardizedFileURL.path
        let ordner = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        decisionHandler(pfad.hasPrefix(ordner) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    /// Der Web-Prozess ist abgestürzt: die Animation ist weg, der Player verschwindet.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failed = true
        isPlaying = false
    }

    /// Abgebrochene Ladevorgänge (-999, „Frame load interrupted“ 102 von WebKit)
    /// sind kein Fehler der Seite — etwa wenn die Navigation selbst abgelehnt wurde.
    private func loadFailed(_ error: Error) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain, e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain", e.code == 102 { return }
        failed = true
    }
}

// MARK: - Ansichten

private struct ExplainerWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Bühne (16:10) mit der Leiste direkt darunter. Die Bühne nimmt die angebotene
/// Breite ein, höchstens aber so viel, dass sie `maxStageHeight` nicht überschreitet;
/// die Leiste ist genauso breit und mittig.
private struct StageLayout: Layout {
    static let aspect: CGFloat = 16.0 / 10.0
    var maxStageHeight: CGFloat?
    var spacing: CGFloat = 6

    private func stageWidth(_ proposal: ProposedViewSize) -> CGFloat {
        let angeboten = proposal.width.map { $0.isFinite ? $0 : nil } ?? nil
        var breite = angeboten ?? (maxStageHeight.map { $0 * Self.aspect } ?? 640)
        if let maxStageHeight { breite = min(breite, maxStageHeight * Self.aspect) }
        return max(0, breite)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let breite = stageWidth(proposal)
        let leiste = subviews[1].sizeThatFits(ProposedViewSize(width: breite, height: nil)).height
        return CGSize(width: breite, height: breite / Self.aspect + spacing + leiste)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let breite = min(bounds.width, stageWidth(proposal))
        let hoehe = breite / Self.aspect
        let x = bounds.midX - breite / 2
        subviews[0].place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: breite, height: hoehe))
        let leiste = subviews[1].sizeThatFits(ProposedViewSize(width: breite, height: nil)).height
        subviews[1].place(at: CGPoint(x: x, y: bounds.minY + hoehe + spacing), anchor: .topLeading,
                          proposal: ProposedViewSize(width: breite, height: leiste))
    }
}

/// Bühne im Format 16:10 mit leichter, mittiger Leiste darunter.
struct ExplainerView: View {
    @ObservedObject var controller: ExplainerController
    /// Obergrenze für die Höhe der Bühne (ohne Leiste); `nil` = nur die Breite zählt.
    var maxStageHeight: CGFloat?

    init(controller: ExplainerController, maxStageHeight: CGFloat? = nil) {
        self.controller = controller
        self.maxStageHeight = maxStageHeight
    }

    var body: some View {
        if !controller.failed {
            StageLayout(maxStageHeight: maxStageHeight) {
                ExplainerWebView(webView: controller.webView)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))
                controls
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            controlButton(controller.isPlaying ? "pause.fill" : "play.fill",
                          help: controller.isPlaying ? Loc.t("Pause") : Loc.t("Abspielen"),
                          action: controller.togglePlay)
            controlButton("arrow.counterclockwise", help: Loc.t("Neu starten"), action: controller.restart)
            controlButton(controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                          help: controller.isMuted ? Loc.t("Ton an") : Loc.t("Ton aus"),
                          action: controller.toggleMute)
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        ExplainerIconButton(symbol: symbol, action: action)
            .help(help)
            .accessibilityLabel(help)
    }
}

/// Randloser Symbol-Knopf: gedämpft, beim Überfahren heller, beim Drücken blasser.
private struct ExplainerIconButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: hovering ? 0.95 : 0.62))
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
