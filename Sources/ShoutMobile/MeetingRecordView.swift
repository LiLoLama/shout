import SwiftUI

/// Vollbild-Aufnahme fürs Meeting: Handy auf den Tisch, aufnehmen, fertig.
///
/// Bewusst reduziert — während einer Besprechung will niemand eine Oberfläche
/// bedienen. Große Zeitanzeige, ein Pegel als Lebenszeichen, Pause und Stopp.
struct MeetingRecordView: View {
    @ObservedObject var recorder: MeetingRecorder
    /// Wird mit der fertigen Aufnahme gerufen; die Datei geht danach als normaler
    /// Auftrag in die Warteschlange.
    let onFinished: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Einmaliger Hinweis auf die Rechtslage. Ein Mitschnitt eines Gesprächs ohne
    /// Einverständnis der anderen ist in Deutschland und Österreich strafbar, und
    /// eine App, die genau dieses Werkzeug in die Hand gibt, sollte das einmal sagen.
    @AppStorage("meetingLegalHintShown") private var hintShown = false
    @State private var showHint = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Text(Self.clock(recorder.duration))
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(recorder.isPaused ? .secondary : .primary)
                    .contentTransition(.numericText())

                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                level

                Spacer()

                if let error {
                    Text(error)
                        .font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                controls
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Loc.t("Meeting aufnehmen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Loc.t("Abbrechen"), role: .destructive) {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(recorder.isRecording)
            .onAppear {
                if hintShown { begin() } else { showHint = true }
            }
            .alert(Loc.t("Kurz vorweg"), isPresented: $showHint) {
                Button(Loc.t("Verstanden")) {
                    hintShown = true
                    begin()
                }
                Button(Loc.t("Abbrechen"), role: .cancel) { dismiss() }
            } message: {
                Text(Loc.t("Ein Gespräch mitzuschneiden ist ohne Einverständnis der anderen Beteiligten in Deutschland und Österreich strafbar. Frag kurz, bevor du aufnimmst."))
            }
        }
    }

    // MARK: - Teile

    private var status: String {
        if !recorder.isRecording { return Loc.t("Bereit") }
        return recorder.isPaused ? Loc.t("Pausiert") : Loc.t("Nimmt auf …")
    }

    /// Schlichter Pegelbalken statt Wellenform: Er beantwortet die einzige Frage, die
    /// während einer Aufnahme zählt — kommt überhaupt Ton an?
    private var level: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(Color.shoutLive)
                    .frame(width: geo.size.width * CGFloat(recorder.isPaused ? 0 : recorder.level))
                    .animation(.linear(duration: 0.1), value: recorder.level)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 48)
    }

    private var controls: some View {
        HStack(spacing: 40) {
            Button {
                recorder.isPaused ? recorder.resume() : recorder.pause()
            } label: {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.secondary.opacity(0.16)))
            }
            .disabled(!recorder.isRecording)

            Button {
                guard let url = recorder.stop() else { dismiss(); return }
                onFinished(url)
                dismiss()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(Color.shoutLive))
            }
            .disabled(!recorder.isRecording)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func begin() {
        do {
            try recorder.start()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// „1:02:44" bzw. „7:31" — ohne führende Stunde, solange keine gebraucht wird.
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
