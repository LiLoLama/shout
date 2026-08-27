import UIKit

/// Die Extension ist bewusst kein vermeintliches Inline-Mikrofon: iOS erlaubt
/// Tastatur-Erweiterungen keinen Mikrofonzugriff. Sie erklärt deshalb den echten
/// Zwei-Schritt-Weg und hält dessen Zustand zwischen Host-App und shout. sichtbar.
final class KeyboardViewController: UIInputViewController {

    private let accent = UIColor(red: 1.0, green: 0.29, blue: 0.04, alpha: 1)

    private let titleLabel = UILabel()
    private let flowLabel = UILabel()
    private let recordButton = UIButton(type: .system)
    private let insertButton = UIButton(type: .system)
    private let setupButton = UIButton(type: .system)
    private let statusIcon = UIImageView()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let statusCard = UIStackView()
    private let globeButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)

    private var contentStack: UIStackView?
    private var keyboardHeightConstraint: NSLayoutConstraint?

    private var deleteDelay: DispatchWorkItem?
    private var deleteTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        applyAppearance()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshState()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        globeButton.isHidden = !needsInputModeSwitchKey
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        refreshState()
    }

    // MARK: - Aufbau

    private func buildUI() {
        titleLabel.text = "shout."
        titleLabel.font = dynamicFont(.subheadline, weight: .heavy)
        titleLabel.adjustsFontForContentSizeCategory = true

        flowLabel.text = Loc.t("1 Aufnehmen · 2 Hier einfügen")
        flowLabel.font = .preferredFont(forTextStyle: .caption1)
        flowLabel.adjustsFontForContentSizeCategory = true
        flowLabel.textAlignment = .right
        flowLabel.numberOfLines = 1

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), flowLabel])
        header.axis = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8
        header.setContentHuggingPriority(.required, for: .vertical)
        header.setContentCompressionResistancePriority(.required, for: .vertical)

        configureButton(
            recordButton,
            title: Loc.t("In shout. aufnehmen"),
            image: "mic.fill",
            prominence: .primary
        )
        recordButton.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)
        recordButton.accessibilityHint = Loc.t("Öffnet shout. für die Aufnahme. Kehre danach zu diesem Textfeld zurück.")
        recordButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true

        configureButton(insertButton, title: Loc.t("Diktat einfügen"), image: "text.insert", prominence: .secondary)
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        insertButton.accessibilityHint = Loc.t("Fügt das zuletzt in shout. aufgenommene Diktat in dieses Textfeld ein.")
        insertButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        configureButton(setupButton, title: Loc.t("Vollzugriff einrichten"), image: "gearshape", prominence: .secondary)
        setupButton.addTarget(self, action: #selector(setupTapped), for: .touchUpInside)
        setupButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        statusIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        statusIcon.setContentHuggingPriority(.required, for: .horizontal)
        statusIcon.accessibilityElementsHidden = true

        statusLabel.font = dynamicFont(.footnote, weight: .semibold)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        detailLabel.font = .preferredFont(forTextStyle: .caption1)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0

        let statusText = UIStackView(arrangedSubviews: [statusLabel, detailLabel])
        statusText.axis = .vertical
        statusText.spacing = 2
        statusText.alignment = .fill

        statusCard.addArrangedSubview(statusIcon)
        statusCard.addArrangedSubview(statusText)
        statusCard.axis = .horizontal
        statusCard.alignment = .top
        statusCard.spacing = 10
        statusCard.isLayoutMarginsRelativeArrangement = true
        statusCard.directionalLayoutMargins = .init(top: 9, leading: 10, bottom: 9, trailing: 10)
        statusCard.layer.cornerRadius = 12
        statusCard.isAccessibilityElement = true

        let bottomRow = makeBottomRow()

        let stack = UIStackView(arrangedSubviews: [header, recordButton, insertButton, statusCard, setupButton, bottomRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        contentStack = stack
        let height = view.heightAnchor.constraint(equalToConstant: 276)
        height.priority = .init(999)
        keyboardHeightConstraint = height

        NSLayoutConstraint.activate([
            height,
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
        ])
    }

    /// Die sichtbaren Zustände besitzen unterschiedlich viele Zeilen. Eine starre
    /// Höhe ließ UIKit den Header im kurzen Vollzugriff-Zustand aufziehen und
    /// erzeugte auf echten Geräten einen großen Leerbalken. Die Tastatur folgt
    /// deshalb ihrer tatsächlich benötigten, Dynamic-Type-fähigen Inhaltshöhe.
    private func updateKeyboardHeight() {
        guard let stack = contentStack,
              let height = keyboardHeightConstraint,
              view.bounds.width > 24 else { return }

        let availableWidth = view.bounds.width - 24
        let fitted = stack.systemLayoutSizeFitting(
            CGSize(width: availableWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let desiredHeight = ceil(fitted.height + 16)
        guard desiredHeight > 0, abs(height.constant - desiredHeight) > 0.5 else { return }
        height.constant = desiredHeight
    }

    private func makeBottomRow() -> UIStackView {
        configureIconButton(globeButton, icon: "globe", label: Loc.t("Nächste Tastatur"))
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let space = UIButton(type: .system)
        configureButton(space, title: Loc.t("Leerzeichen"), image: nil, prominence: .key)
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)

        configureIconButton(deleteButton, icon: "delete.left", label: Loc.t("Löschen"))
        deleteButton.addTarget(self, action: #selector(deleteTouchDown), for: .touchDown)
        deleteButton.addTarget(self, action: #selector(deleteTouchEnded),
                               for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])

        configureIconButton(returnButton, icon: "return", label: Loc.t("Zeilenumbruch"))
        returnButton.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [globeButton, space, deleteButton, returnButton])
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fill
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        for button in [globeButton, deleteButton, returnButton] {
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        }
        return row
    }

    private enum ButtonProminence: Equatable { case primary, secondary, key }

    private func configureButton(_ button: UIButton, title: String, image: String?,
                                 prominence: ButtonProminence) {
        var configuration: UIButton.Configuration = prominence == .primary ? .filled() : .gray()
        configuration.title = title
        configuration.image = image.flatMap(UIImage.init(systemName:))
        configuration.imagePadding = 8
        configuration.cornerStyle = prominence == .primary ? .large : .medium
        configuration.baseBackgroundColor = prominence == .primary ? accent : .secondarySystemFill
        configuration.baseForegroundColor = prominence == .primary ? .white : .label
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak self] incoming in
            var outgoing = incoming
            outgoing.font = self?.dynamicFont(prominence == .primary ? .headline : .body,
                                               weight: prominence == .primary ? .bold : .medium)
            return outgoing
        }
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    private func configureIconButton(_ button: UIButton, icon: String, label: String) {
        configureButton(button, title: "", image: icon, prominence: .key)
        button.configuration?.imagePadding = 0
        button.accessibilityLabel = label
    }

    private func dynamicFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let preferred = UIFont.preferredFont(forTextStyle: style)
        return UIFont.systemFont(ofSize: preferred.pointSize, weight: weight)
    }

    private func applyAppearance() {
        // Keine Tastaturfarbe nachbauen: Der Keyboard-Host zeichnet bereits das
        // passende translucente Material samt oberer Rundung und Dock-Fläche. Eine
        // deckende Root-Farbe erzeugt auf echten Geräten eine sichtbare Naht.
        view.isOpaque = false
        view.backgroundColor = .clear
        inputView?.isOpaque = false
        inputView?.backgroundColor = .clear
        titleLabel.textColor = accent
        flowLabel.textColor = .secondaryLabel
        statusLabel.textColor = .label
        detailLabel.textColor = .secondaryLabel
        statusCard.backgroundColor = .tertiarySystemBackground
    }

    // MARK: - Zustand

    private func refreshState() {
        defer { view.setNeedsLayout() }
        guard hasFullAccess else {
            insertButton.isHidden = true
            setupButton.isHidden = false
            showStatus(
                icon: "lock.fill",
                title: Loc.t("Zum Einfügen fehlt noch Vollzugriff"),
                detail: Loc.t("Öffne die Anleitung. shout. verarbeitet weiterhin alles lokal auf deinem Gerät.")
            )
            return
        }

        setupButton.isHidden = true
        if let text = AppGroup.pendingDictation() {
            let flat = text.replacingOccurrences(of: "\n", with: " ")
            let preview = flat.count > 64 ? String(flat.prefix(64)) + "…" : flat
            insertButton.isHidden = false
            showStatus(icon: "checkmark.circle.fill",
                       title: Loc.t("Bereit zum Einfügen"), detail: "„\(preview)“")
            return
        }

        insertButton.isHidden = true
        switch AppGroup.phase() {
        case .openingApp:
            showStatus(icon: "arrow.up.forward.app", title: Loc.t("shout. wird geöffnet …"),
                       detail: Loc.t("Nimm dort auf und kehre danach zu diesem Textfeld zurück."))
        case .recording:
            showStatus(icon: "waveform", title: Loc.t("Aufnahme läuft in shout."),
                       detail: Loc.t("Stoppe dort die Aufnahme und kehre anschließend hierher zurück."))
        case .processing:
            showStatus(icon: "ellipsis.circle", title: Loc.t("Diktat wird verarbeitet …"),
                       detail: Loc.t("Kehre gleich zu diesem Textfeld zurück."))
        case .failed:
            showStatus(icon: "exclamationmark.triangle", title: Loc.t("Kein neues Diktat"),
                       detail: Loc.t("Öffne shout. und versuch die Aufnahme erneut."))
        case .cancelled:
            showStatus(icon: "xmark.circle", title: Loc.t("Aufnahme verworfen"),
                       detail: Loc.t("Du kannst jederzeit ein neues Diktat aufnehmen."))
        case .expired:
            showStatus(icon: "clock.badge.exclamationmark", title: Loc.t("Das letzte Diktat ist abgelaufen"),
                       detail: Loc.t("Nimm ein neues Diktat auf, damit nichts Veraltetes eingefügt wird."))
        case .inserted:
            showStatus(icon: "checkmark", title: Loc.t("Diktat eingefügt"),
                       detail: Loc.t("Du kannst direkt weiterarbeiten oder erneut aufnehmen."))
        case .idle, .ready:
            showStatus(icon: "1.circle", title: Loc.t("Zuerst in shout. aufnehmen"),
                       detail: Loc.t("Danach zurückkehren und hier auf Einfügen tippen."))
        }
    }

    private func showStatus(icon: String, title: String, detail: String) {
        statusIcon.image = UIImage(systemName: icon)
        statusIcon.tintColor = accent
        statusLabel.text = title
        detailLabel.text = detail
        statusCard.accessibilityLabel = title
        statusCard.accessibilityValue = detail
    }

    // MARK: - Aktionen

    @objc private func recordTapped() {
        if hasFullAccess {
            AppGroup.clearPending()
            AppGroup.setPhase(.openingApp)
        }
        refreshState()
        openMainApp(host: "dictate")
    }

    @objc private func setupTapped() {
        openMainApp(host: "keyboard-settings")
    }

    @objc private func insertTapped() {
        guard hasFullAccess, let text = AppGroup.pendingDictation() else {
            refreshState()
            return
        }
        textDocumentProxy.insertText(text)
        AppGroup.clearPending()
        AppGroup.setPhase(.inserted)
        refreshState()
    }

    @objc private func spaceTapped() { textDocumentProxy.insertText(" ") }
    @objc private func returnTapped() { textDocumentProxy.insertText("\n") }

    @objc private func deleteTouchDown() {
        textDocumentProxy.deleteBackward()
        deleteDelay?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
                self?.textDocumentProxy.deleteBackward()
            }
        }
        deleteDelay = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    @objc private func deleteTouchEnded() {
        deleteDelay?.cancel()
        deleteDelay = nil
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    /// Tastatur-Erweiterungen besitzen keinen direkten UIApplication-Zugriff. Die
    /// Responder-Kette bleibt nötig; Fehlschläge werden jetzt sichtbar gespeichert.
    private func openMainApp(host: String) {
        guard let url = URL(string: "shout://\(host)") else { return }
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { [weak self] success in
                    guard let self, !success else { return }
                    if self.hasFullAccess { AppGroup.setPhase(.failed) }
                    self.refreshState()
                }
                return
            }
            responder = current.next
        }
        if hasFullAccess { AppGroup.setPhase(.failed) }
        refreshState()
    }
}
