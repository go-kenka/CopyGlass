import SwiftUI

/// Floating toolbar shown under the captured region while the frozen overlay is up — the Feishu
/// arrangement: drawing tools first, then stroke width and colour, then undo/redo and the actions
/// (extract text, pin, save, copy, cancel).
struct ScreenshotToolbarContainer: View {
    @ObservedObject var session: CaptureSession
    /// Passed in explicitly (and pushed into the environment below): this view is hosted in a bare
    /// NSHostingView floating over the frozen screen, where \.appLanguage would otherwise fall back
    /// to its default of English instead of the language chosen in settings.
    let language: AppLanguage
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPin: () -> Void
    let onExtractText: () -> Void
    /// Copies recognized text and then finishes the capture (the overlay closes).
    let onCopyText: (String) -> Void
    let onCancel: () -> Void

    private var lang: AppLanguage { language }

    var body: some View {
        Group {
            switch session.panel {
            case .tools:
                toolbar
            case .ocr:
                ocrPanel
            }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.appLanguage, language)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 3) {
            ForEach(AnnotationTool.allCases) { tool in
                iconButton(
                    tool.systemImage,
                    isSelected: session.tool == tool,
                    help: tool.title(lang)
                ) {
                    session.tool = tool
                }
            }

            if session.tool != .select {
            separator

            ForEach(strokeWidths, id: \.self) { width in
                Button {
                    session.lineWidth = width
                } label: {
                    Circle()
                        .fill(Color.white.opacity(session.lineWidth == width ? 1 : 0.55))
                        .frame(width: dotSize(for: width), height: dotSize(for: width))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(session.lineWidth == width ? Color.accentColor.opacity(0.55) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t(.strokeWidth, lang: lang))
            }

            separator

            ForEach(AnnotationColor.palette, id: \.self) { swatch in
                Button {
                    session.color = swatch
                } label: {
                    Circle()
                        .fill(Color(nsColor: swatch.nsColor))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().stroke(
                                session.color == swatch ? Color.accentColor : Color.white.opacity(0.35),
                                lineWidth: session.color == swatch ? 2 : 1
                            )
                        )
                        .frame(width: 22, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            }

            separator

            iconButton("arrow.uturn.backward", enabled: session.canUndo, help: L10n.t(.undo, lang: lang)) {
                session.undo()
            }
            iconButton("arrow.uturn.forward", enabled: session.canRedo, help: L10n.t(.redo, lang: lang)) {
                session.redo()
            }
            iconButton("trash", enabled: session.hasAnnotations, help: L10n.t(.clear, lang: lang)) {
                session.clearAnnotations()
            }

            separator

            iconButton("text.viewfinder", help: L10n.t(.ocrTitle, lang: lang)) { onExtractText() }
            iconButton("pin", help: L10n.t(.pin, lang: lang)) { onPin() }
            iconButton("square.and.arrow.down", help: L10n.t(.save, lang: lang)) { onSave() }
            iconButton("doc.on.doc", isProminent: true, help: L10n.t(.copy, lang: lang)) { onCopy() }
            iconButton("xmark", help: L10n.t(.cancel, lang: lang)) { onCancel() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(panelBackground)
    }

    private var strokeWidths: [CGFloat] { [2, 4, 8] }

    private func dotSize(for width: CGFloat) -> CGFloat {
        min(16, 4 + width)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 3)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    // MARK: - OCR panel

    private var ocrPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    session.panel = .tools
                } label: {
                    Image(systemName: "chevron.left").frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(L10n.t(.back, lang: lang))

                Image(systemName: "text.viewfinder")
                Text(L10n.t(.ocrTitle, lang: lang)).font(.headline)

                Spacer(minLength: 8)

                if session.statusMessage != nil || session.hasRecognizedText {
                    Toggle(L10n.t(.ocrShowBoxes, lang: lang), isOn: $session.showOCRBoxes)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }

                Button(L10n.t(.copyAll, lang: lang)) {
                    onCopyText(session.ocrResult?.plainText ?? "")
                }
                .disabled(!session.hasRecognizedText)

                Button {
                    session.panel = .tools
                } label: {
                    Image(systemName: "xmark").frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(L10n.t(.close, lang: lang))
            }

            if session.isRecognizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t(.ocrRecognizing, lang: lang)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else if session.hasRecognizedText, let result = session.ocrResult {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(result.blocks) { block in
                            Button {
                                onCopyText(block.text)
                            } label: {
                                Text(block.text)
                                    .font(.system(size: 12))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(L10n.t(.copy, lang: lang))
                        }
                    }
                    .padding(.trailing, 4)
                }
            } else {
                Text(session.statusMessage ?? L10n.t(.noTextFound, lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            if let status = session.statusMessage, session.hasRecognizedText {
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 420, height: 320)
        .background(panelBackground)
    }

    // MARK: - Buttons

    @ViewBuilder
    private func iconButton(
        _ systemName: String,
        isSelected: Bool = false,
        isProminent: Bool = false,
        enabled: Bool = true,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(background(for: isSelected, isProminent: isProminent))
                )
                .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.35))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private func background(for isSelected: Bool, isProminent: Bool) -> Color {
        if isSelected { return Color.accentColor.opacity(0.85) }
        if isProminent { return Color.accentColor.opacity(0.5) }
        return Color.clear
    }
}
