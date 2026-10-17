import Foundation
import AppKit
import CoreGraphics
import SwiftUI

/// State backing the screenshot editor window: annotation shapes, OCR results and actions.
final class ScreenshotEditorModel: ObservableObject {
    let originalImage: CGImage

    @Published var shapes: [AnnotationShape] = []
    @Published var tool: AnnotationTool = .rectangle
    @Published var color: AnnotationColor = AnnotationColor.palette[0]
    @Published var lineWidth: CGFloat = 4
    @Published var ocrResult: OCRResult?
    @Published var isRecognizing = false
    /// Off by default, matching the capture toolbar's text-area highlight toggle.
    @Published var showOCRBoxes = false
    @Published var showOCRPanel = false
    @Published var statusMessage: String?

    private var undoStack: [[AnnotationShape]] = []
    private var redoStack: [[AnnotationShape]] = []

    init(image: CGImage) {
        self.originalImage = image
    }

    var imagePixelSize: CGSize {
        CGSize(width: originalImage.width, height: originalImage.height)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasAnnotations: Bool { !shapes.isEmpty }

    // MARK: - Editing

    func commit(_ shape: AnnotationShape) {
        pushUndo()
        shapes.append(shape)
        statusMessage = nil
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(shapes)
        shapes = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(shapes)
        shapes = next
    }

    func clearAnnotations() {
        guard !shapes.isEmpty else { return }
        pushUndo()
        shapes.removeAll()
    }

    private func pushUndo() {
        undoStack.append(shapes)
        if undoStack.count > 60 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func nextNumberLabel() -> Int {
        shapes.filter { $0.tool == .number }.count + 1
    }

    func flattenedImage() -> CGImage {
        AnnotationRenderer.render(base: originalImage, shapes: shapes) ?? originalImage
    }

    // MARK: - OCR

    func recognizeText(openPanel: Bool = true) {
        if openPanel {
            showOCRPanel = true
        }
        guard !isRecognizing else { return }
        isRecognizing = true
        statusMessage = L10n.t(.ocrRecognizing, lang: AppLanguage.current)
        let image = originalImage
        Task {
            let result = await OCRService.recognizeAsync(image: image)
            await MainActor.run {
                self.isRecognizing = false
                self.statusMessage = nil
                switch result {
                case .success(let ocr):
                    self.ocrResult = ocr
                    if ocr.isEmpty {
                        self.statusMessage = L10n.t(.ocrEmpty, lang: AppLanguage.current)
                    }
                case .failure(let error):
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func copyOCRText() {
        guard let text = ocrResult?.plainText, !text.isEmpty else { return }
        ScreenshotClipboard.copy(text: text)
        statusMessage = L10n.t(.copied, lang: AppLanguage.current)
    }

    func copyBlock(_ block: OCRTextBlock) {
        ScreenshotClipboard.copy(text: block.text)
        statusMessage = L10n.t(.copied, lang: AppLanguage.current)
    }

    // MARK: - Actions

    func copyFlattenedToPasteboard() {
        ScreenshotClipboard.copy(image: flattenedImage())
        statusMessage = L10n.t(.copiedToClipboard, lang: AppLanguage.current)
    }

    func saveFlattened() {
        ScreenshotSaver.save(image: flattenedImage(), suggestedName: nil, window: nil)
    }

    func pinFlattened(at point: CGPoint?) {
        PinWindowManager.shared.pin(image: flattenedImage(), at: point)
        statusMessage = L10n.t(.pinned, lang: AppLanguage.current)
    }
}
