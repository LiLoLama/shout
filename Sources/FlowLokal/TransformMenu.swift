import SwiftUI

/// Was Panel und Seite für den Zauberstab brauchen.
@MainActor
struct NoteToolbox {
    let runner: NoteTransformRunner
    let transforms: TransformStore
    /// „Per Sprache …“ — `nil`, solange es keinen Weg gibt, eine Anweisung aufzunehmen.
    let onVoiceInstruction: ((NoteEditorSession) -> Void)?
}

/// Der Zauberstab: eingebaute Transforms, eigene, per Sprache, zuletzt gesprochen.
struct TransformMenu: View {
    let tools: NoteToolbox
    @ObservedObject private var runner: NoteTransformRunner
    @ObservedObject private var transforms: TransformStore
    @ObservedObject private var session: NoteEditorSession
    private let onActivate: () -> Void

    init(tools: NoteToolbox, session: NoteEditorSession, onActivate: @escaping () -> Void = {}) {
        self.tools = tools
        _runner = ObservedObject(wrappedValue: tools.runner)
        _transforms = ObservedObject(wrappedValue: tools.transforms)
        _session = ObservedObject(wrappedValue: session)
        self.onActivate = onActivate
    }

    var body: some View {
        Menu {
            ForEach(BuiltinTransform.allCases) { t in
                Button(t.name) {
                    onActivate()
                    runner.run(instruction: t.instruction, working: t.working, done: t.done, on: session)
                }
            }
            if !transforms.custom.isEmpty {
                Divider()
                ForEach(transforms.custom) { t in
                    Button(t.name) {
                        onActivate()
                        runner.run(instruction: t.prompt,
                                   working: Loc.f("„%@“ wird angewendet …", t.name),
                                   done: Loc.f("„%@“ angewendet", t.name),
                                   on: session)
                    }
                }
            }
            if let sprechen = tools.onVoiceInstruction {
                Divider()
                Button(Loc.t("Per Sprache …")) { onActivate(); sprechen(session) }
                if let letzte = runner.lastInstruction {
                    Button(Loc.f("Zuletzt: %@", NoteTransformRunner.short(letzte))) {
                        onActivate()
                        runner.runInstruction(letzte, on: session)
                    }
                }
            }
        } label: {
            Image(systemName: "wand.and.stars").font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!runner.isAvailable || session.isTransforming || session.status == .placeholder)
        .help(runner.isAvailable ? Loc.t("Text umarbeiten") : Loc.t("Unter Modelle ein Textmodell wählen"))
    }
}
