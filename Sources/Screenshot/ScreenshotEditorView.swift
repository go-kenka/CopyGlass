import SwiftUI

/// Editor window content: annotation tools, canvas, OCR sidebar and the action bar.
struct ScreenshotEditorView: View {
    @ObservedObject var model: ScreenshotEditorModel
    var onClose: () -> Void
    @Environment(\.appLanguage) private var lang

    var body: some View {
        VStack(spacing: 0) {
            toolBar
            Divider()
            HStack(spacing: 0) {
                AnnotationCanvas(model: model)
                    .frame(minWidth: 320, minHeight: 220)
                if model.showOCRPanel {
                    Divider()
                    ocrPanel
                }
            }
            Divider()
            actionBar
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.001))
    }

    // MARK: Toolbar

    private var toolBar: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tool.title(lang))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(model.tool == tool ? Color.accentColor.opacity(0.28) : Color.clear)
                )
            }

            Divider().frame(height: 18)

            ForEach(AnnotationColor.palette, id: \.self) { swatch in
                Button {
                    model.color = swatch
                } label: {
                    Circle()
                        .fill(Color(nsColor: swatch.nsColor))
                        .frame(width: 17, height: 17)
                        .overlay(
                            Circle().stroke(
                                model.color == swatch ? Color.primary.opacity(0.9) : Color.primary.opacity(0.18),
                                lineWidth: model.color == swatch ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .help(swatch.nsColor.accessibilityName)
            }

            Divider().frame(height: 18)

            Slider(value: $model.lineWidth, in: 1...18)
                .frame(width: 88)
            Text(String(Int(model.lineWidth)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Spacer(minLength: 8)

            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndo)
            .help(L10n.t(.undo, lang: lang))

            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.plain)
            .disabled(!model.canRedo)
            .help(L10n.t(.redo, lang: lang))

            Button {
                model.clearAnnotations()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(!model.hasAnnotations)
            .help(L10n.t(.clear, lang: lang))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: OCR panel

    private var ocrPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.viewfinder")
                Text(L10n.t(.ocrTitle, lang: lang)).font(.headline)
                Spacer()
                Button(L10n.t(.copyAll, lang: lang)) {
                    model.copyOCRText()
                }
                .disabled((model.ocrResult?.isEmpty ?? true))
            }

            Toggle(L10n.t(.ocrShowBoxes, lang: lang), isOn: $model.showOCRBoxes)
                .toggleStyle(.checkbox)

            if model.isRecognizing {
                ProgressView().controlSize(.small)
                Spacer()
            } else if let result = model.ocrResult, !result.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(result.blocks) { block in
                            Button {
                                model.copyBlock(block)
                            } label: {
                                Text(block.text)
                                    .font(.system(size: 12))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help(L10n.t(.copy, lang: lang))
                        }
                    }
                    .padding(.trailing, 4)
                }
            } else {
                Text(L10n.t(.ocrEmpty, lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(model.statusMessage ?? sizeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                model.recognizeText()
            } label: {
                Label(L10n.t(.ocrTitle, lang: lang), systemImage: "text.viewfinder")
            }

            Button {
                model.pinFlattened(at: nil)
            } label: {
                Label(L10n.t(.pin, lang: lang), systemImage: "pin")
            }

            Button {
                model.saveFlattened()
            } label: {
                Label(L10n.t(.save, lang: lang), systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)

            Button {
                model.copyFlattenedToPasteboard()
            } label: {
                Label(L10n.t(.copy, lang: lang), systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button(L10n.t(.close, lang: lang)) {
                onClose()
            }
            .keyboardShortcut("w", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var sizeLabel: String {
        let size = model.imagePixelSize
        return String(format: "%.0f x %.0f px", size.width, size.height)
    }
}
