import UIKit

/// shout-Tastatur: eine Diktier-Tastatur für beliebige Apps.
///
/// iOS verbietet Tastatur-Erweiterungen den Mikrofonzugriff. Der Weg ist daher:
///   1. „Diktieren" öffnet die shout-App (shout://dictate) → dort wird aufgenommen
///      und lokal transkribiert, das Ergebnis landet in der geteilten App Group.
///   2. Zurückwischen zur ursprünglichen App → „Einfügen" schreibt den Text ins Feld.
///
/// „Einfügen" braucht Vollzugriff (App-Group-Zugriff) — darauf weist die Tastatur hin.
final class KeyboardViewController: UIInputViewController {

    private let accent = UIColor(red: 1.0, green: 0.29, blue: 0.04, alpha: 1)
    private let panel  = UIColor(red: 0.145, green: 0.145, blue: 0.165, alpha: 1)

    private var einfuegenButton = UIButton(type: .system)
    private var hintLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.105, green: 0.105, blue: 0.125, alpha: 1)
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshState()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        // Nach der Rückkehr aus der App aktualisieren (frisches Diktat anzeigen).
        refreshState()
    }

    // MARK: - Aufbau

    private func buildUI() {
        // Höhe der Tastatur festlegen.
        let height = view.heightAnchor.constraint(equalToConstant: 264)
        height.priority = .init(999)
        height.isActive = true

        let title = UILabel()
        title.text = "shout."
        title.font = .systemFont(ofSize: 15, weight: .heavy)
        title.textColor = accent

        let diktieren = primaryButton(title: "  Diktieren", icon: "mic.fill")
        diktieren.addTarget(self, action: #selector(diktierenTapped), for: .touchUpInside)
        diktieren.heightAnchor.constraint(equalToConstant: 64).isActive = true

        einfuegenButton = secondaryButton(title: "Einfügen")
        einfuegenButton.addTarget(self, action: #selector(einfuegenTapped), for: .touchUpInside)
        einfuegenButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        einfuegenButton.titleLabel?.lineBreakMode = .byTruncatingTail

        hintLabel.text = "Für das Einfügen bitte Vollzugriff erlauben:\nEinstellungen → Allgemein → Tastatur → shout."
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .center

        let bottomRow = makeBottomRow()

        let stack = UIStackView(arrangedSubviews: [title, diktieren, einfuegenButton, hintLabel, bottomRow])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
        ])
        stack.setCustomSpacing(6, after: title)
    }

    private func makeBottomRow() -> UIStackView {
        let globe = iconButton("globe")
        globe.addTarget(self, action: #selector(nextKeyboardTapped), for: .touchUpInside)

        let space = secondaryButton(title: "Leerzeichen")
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)

        let back = iconButton("delete.left")
        back.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)

        let ret = iconButton("return")
        ret.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [globe, space, back, ret])
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fill
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)   // Leerzeichen füllt
        row.heightAnchor.constraint(equalToConstant: 44).isActive = true
        for b in [globe, back, ret] { b.widthAnchor.constraint(equalToConstant: 52).isActive = true }
        return row
    }

    // MARK: - Button-Fabriken

    private func primaryButton(title: String, icon: String) -> UIButton {
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.image = UIImage(systemName: icon)
        cfg.imagePadding = 8
        cfg.baseBackgroundColor = accent
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .large
        let b = UIButton(configuration: cfg)
        b.titleLabel?.font = .systemFont(ofSize: 19, weight: .bold)
        return b
    }

    private func secondaryButton(title: String) -> UIButton {
        var cfg = UIButton.Configuration.gray()
        cfg.title = title
        cfg.baseBackgroundColor = panel
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .medium
        let b = UIButton(configuration: cfg)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        return b
    }

    private func iconButton(_ icon: String) -> UIButton {
        var cfg = UIButton.Configuration.gray()
        cfg.image = UIImage(systemName: icon)
        cfg.baseBackgroundColor = panel
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .medium
        return UIButton(configuration: cfg)
    }

    // MARK: - Zustand

    private func refreshState() {
        let pending = hasFullAccess ? AppGroup.pendingDictation() : nil
        if let text = pending {
            let flat = text.replacingOccurrences(of: "\n", with: " ")
            let preview = flat.count > 42 ? String(flat.prefix(42)) + "…" : flat
            einfuegenButton.configuration?.title = "Einfügen: \u{201E}\(preview)\u{201C}"
            einfuegenButton.isHidden = false
        } else {
            einfuegenButton.isHidden = true
        }
        // Hinweis nur, solange Vollzugriff fehlt.
        hintLabel.isHidden = hasFullAccess
    }

    // MARK: - Aktionen

    @objc private func diktierenTapped() {
        openMainApp()
    }

    @objc private func einfuegenTapped() {
        guard hasFullAccess, let text = AppGroup.pendingDictation() else { return }
        textDocumentProxy.insertText(text)
        AppGroup.clearPending()
        refreshState()
    }

    @objc private func spaceTapped()     { textDocumentProxy.insertText(" ") }
    @objc private func returnTapped()    { textDocumentProxy.insertText("\n") }
    @objc private func backspaceTapped() { textDocumentProxy.deleteBackward() }
    @objc private func nextKeyboardTapped() { advanceToNextInputMode() }

    /// Öffnet die Haupt-App aus der Erweiterung heraus. Tastatur-Erweiterungen
    /// haben keinen direkten UIApplication-Zugriff — daher die Responder-Kette
    /// hochlaufen, bis eine UIApplication gefunden ist (offiziell tolerierter Weg).
    private func openMainApp() {
        guard let url = URL(string: "shout://dictate") else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }
}
