import Foundation
import AppKit
import CoreGraphics
import SwiftUI

/// Editing state for one capture while the frozen screen overlay is on screen (Feishu-style
/// in-place editing): the cropped screenshot plus the annotations drawn over it.
final class CaptureSession: ObservableObject {
    /// Which floating panel the capture toolbar shows.
    enum Panel: Equatable {
        case tools
        case ocr
    }

    /// The captured region, in pixels, top-left origin. It is replaced when the user moves or
    /// resizes the capture frame after drawing it.
    private(set) var image: CGImage

    @Published private(set) var shapes: [AnnotationShape] = []
    /// Pointer tool by default so annotations can be moved right after capturing.
    @Published var tool: AnnotationTool = .select
    /// Shape currently selected for moving/resizing.
    @Published private(set) var selectedShapeID: UUID?
    /// Shape under the pointer, highlighted as a hint that it can be edited.
    @Published private(set) var hoveredShapeID: UUID?
    /// Shape currently open in the inline text editor. It is hidden from the canvas so the text is
    /// not painted twice — once by the renderer, once by the editable field (which shows as a ghost).
    @Published private(set) var textEditingShapeID: UUID?
    @Published var color: AnnotationColor = AnnotationColor.palette[0]
    @Published var lineWidth: CGFloat = 4
    @Published var panel: Panel = .tools
    @Published private(set) var isRecognizing = false
    @Published private(set) var ocrResult: OCRResult?
    /// Highlighting the recognized text areas on the capture is off until the user asks for it.
    @Published var showOCRBoxes = false
    @Published var statusMessage: String?
    /// Index label the next number badge will use.
    @Published private(set) var nextBadge: Int = 1

    /// Called whenever the overlay has to be redrawn.
    var onNeedsDisplay: (() -> Void)?

    private var undoStack: [[AnnotationShape]] = []
    private var redoStack: [[AnnotationShape]] = []
    /// Set while a drag/resize is in flight so the whole gesture is one undo step.
    private var isInteractiveEdit = false
    /// Identifies the capture the running text recognition belongs to; results for an older crop
    /// are dropped when the frame is adjusted meanwhile.
    private var recognitionGeneration = 0

    init(image: CGImage) {
        self.image = image
    }

    /// Swaps in the pixels of an adjusted capture frame (moved or resized while editing).
    ///
    /// Annotations are anchored to the frozen screen, so every point — including the ones kept in
    /// the undo history — is remapped into the new crop's pixel space. `visualScale` compensates
    /// for a changed pixel density (mixed-DPI displays) so strokes keep their on-screen size. Text
    /// recognition results describe the old crop and are discarded.
    func updateCapture(image newImage: CGImage, remapping pointTransform: (CGPoint) -> CGPoint, visualScale: CGFloat = 1) {
        func remap(_ list: [AnnotationShape]) -> [AnnotationShape] {
            list.map { shape in
                var copy = shape
                copy.points = shape.points.map(pointTransform)
                if visualScale != 1, visualScale > 0 {
                    copy.lineWidth *= visualScale
                    copy.blockSize *= visualScale
                }
                return copy
            }
        }
        image = newImage
        shapes = remap(shapes)
        undoStack = undoStack.map(remap)
        redoStack = redoStack.map(remap)
        ocrResult = nil
        statusMessage = nil
        isRecognizing = false
        panel = .tools
        recognitionGeneration += 1
        onNeedsDisplay?()
    }

    var imagePixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasAnnotations: Bool { !shapes.isEmpty }

    var ocrBoxes: [CGRect] {
        guard showOCRBoxes, let result = ocrResult else { return [] }
        return result.blocks.map { $0.pixelBox }
    }

    var hasRecognizedText: Bool {
        !(ocrResult?.isEmpty ?? true)
    }

    var selectedShape: AnnotationShape? {
        selectedShapeID.flatMap { id in shapes.first { $0.id == id } }
    }

    var hoveredShape: AnnotationShape? {
        hoveredShapeID.flatMap { id in shapes.first { $0.id == id } }
    }

    /// Shapes to paint on the canvas: the one being typed into is left out.
    var renderableShapes: [AnnotationShape] {
        guard let textEditingShapeID else { return shapes }
        return shapes.filter { $0.id != textEditingShapeID }
    }

    /// Marks (or clears) the annotation that the inline text editor is showing.
    func setTextEditingShape(_ id: UUID?) {
        guard textEditingShapeID != id else { return }
        textEditingShapeID = id
        onNeedsDisplay?()
    }

    // MARK: - Selecting, moving, resizing

    func setHoveredShape(_ id: UUID?) {
        guard hoveredShapeID != id else { return }
        hoveredShapeID = id
        onNeedsDisplay?()
    }

    func select(_ id: UUID?) {
        guard selectedShapeID != id else { return }
        selectedShapeID = id
        onNeedsDisplay?()
    }

    func shape(with id: UUID) -> AnnotationShape? {
        shapes.first { $0.id == id }
    }

    /// Starts a gesture (move/resize) that becomes a single undo step.
    func beginInteractiveEdit() {
        guard !isInteractiveEdit else { return }
        pushUndo()
        isInteractiveEdit = true
    }

    func endInteractiveEdit() {
        isInteractiveEdit = false
    }

    /// Replaces a shape in place without pushing another undo entry.
    func applyInteractiveChange(_ shape: AnnotationShape) {
        guard let index = shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        shapes[index] = shape
        onNeedsDisplay?()
    }

    /// Replaces a shape as a discrete edit (for example re-typing its text).
    func replace(_ shape: AnnotationShape) {
        guard let index = shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        pushUndo()
        shapes[index] = shape
        onNeedsDisplay?()
    }

    func removeSelectedShape() {
        guard let id = selectedShapeID, let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        shapes.remove(at: index)
        selectedShapeID = nil
        hoveredShapeID = nil
        refreshBadgeCount()
        onNeedsDisplay?()
    }

    /// Nudges the selected shape with the arrow keys.
    func nudgeSelectedShape(by delta: CGSize) {
        guard let selected = selectedShape else { return }
        pushUndo()
        applyInteractiveChange(AnnotationHitTester.translate(selected, by: delta))
    }

    // MARK: - Annotations

    func commit(_ shape: AnnotationShape) {
        pushUndo()
        shapes.append(shape)
        if shape.tool == .number {
            nextBadge = shapes.filter { $0.tool == .number }.count + 1
        }
        // Leave the new annotation selected so its handles are visible right away.
        selectedShapeID = shape.id
        onNeedsDisplay?()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(shapes)
        shapes = previous
        refreshBadgeCount()
        onNeedsDisplay?()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(shapes)
        shapes = next
        refreshBadgeCount()
        onNeedsDisplay?()
    }

    func clearAnnotations() {
        guard !shapes.isEmpty else { return }
        pushUndo()
        shapes.removeAll()
        refreshBadgeCount()
        onNeedsDisplay?()
    }

    private func pushUndo() {
        undoStack.append(shapes)
        if undoStack.count > 80 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    private func refreshBadgeCount() {
        nextBadge = shapes.filter { $0.tool == .number }.count + 1
    }

    // MARK: - Output

    func flattenedImage() -> CGImage {
        AnnotationRenderer.render(base: image, shapes: shapes) ?? image
    }

    // MARK: - OCR

    func recognizeText() {
        guard !isRecognizing else { return }
        panel = .ocr
        // The current crop was already recognized: show that result instantly.
        if let existing = ocrResult, !existing.isEmpty {
            return
        }
        isRecognizing = true
        statusMessage = nil
        let image = self.image
        let generation = recognitionGeneration
        Task {
            let result = await OCRService.recognizeAsync(image: image)
            await MainActor.run {
                // The capture frame may have been adjusted while recognition was running.
                guard generation == self.recognitionGeneration else { return }
                self.isRecognizing = false
                switch result {
                case .success(let ocr):
                    self.ocrResult = ocr
                    if ocr.isEmpty {
                        self.statusMessage = L10n.t(.noTextFound, lang: AppLanguage.current)
                    }
                case .failure(let error):
                    self.statusMessage = error.localizedDescription
                }
                self.onNeedsDisplay?()
            }
        }
    }
}
