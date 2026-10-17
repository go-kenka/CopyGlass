import Foundation
import AppKit

/// Inline editor for text annotations.
///
/// A transparent box with a thin border that grows with the text. The text field inside is exactly
/// one line tall, which is what keeps the caret and the text vertically centred: a taller borderless
/// NSTextField draws its text at the top (measured), which is what made the old grey box look wrong.
final class InlineTextEditor: NSView, NSTextFieldDelegate {
    private let field = NSTextField()
    private let padding = NSEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
    private let minimumTextWidth: CGFloat = 44
    private let font: NSFont

    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private var anchorBaseline: CGFloat?
    private var anchorX: CGFloat = 0

    var stringValue: String {
        get { field.stringValue }
        set {
            field.stringValue = newValue
            resizeToFitText()
        }
    }

    var fontSize: CGFloat { font.pointSize }

    init(text: String, fontSize: CGFloat, textColor: NSColor) {
        self.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        super.init(frame: .zero)

        field.font = font
        field.textColor = textColor
        field.stringValue = text
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        addSubview(field)
        resizeToFitText()
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    /// One line of the annotation font.
    private var lineHeight: CGFloat { ceil(font.ascender - font.descender) }

    // AppKit draws borderless field text with the ink starting about 0.24 * fontSize below the
    // field's top edge and the ink is about 0.90 * fontSize tall (measured for 12...48 pt). Placing
    // the field by these values keeps the text and the caret centred in the box.
    private var inkOffset: CGFloat { round(font.pointSize * 0.24) }
    private var inkHeight: CGFloat { round(font.pointSize * 0.90) }
    private var verticalPadding: CGFloat { max(4, round(font.pointSize * 0.22)) }

    /// How far the field's top edge sits below the box's top edge (negative: slightly above).
    private var fieldTopOffset: CGFloat { verticalPadding - inkOffset }

    /// Baseline position measured from the field's top edge.
    private var baselineFromFieldTop: CGFloat { inkOffset + inkHeight - abs(font.descender) }

    /// Places the box so the text baseline lands on the given y (view coordinates) starting at x.
    func place(baseline: CGFloat, x: CGFloat) {
        anchorBaseline = baseline
        anchorX = x
        let boxTop = baseline + fieldTopOffset + baselineFromFieldTop
        setFrameOrigin(CGPoint(x: x - padding.left, y: boxTop - frame.height))
    }

    /// Focuses the field. Re-editing keeps the caret at the end so typing appends instead of
    /// silently replacing the existing annotation text.
    func focus(selectAll: Bool = false) {
        window?.makeFirstResponder(field)
        guard let editor = field.currentEditor() else { return }
        if selectAll {
            editor.selectAll(nil)
        } else {
            editor.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
        }
    }

    func endEditing() {
        window?.makeFirstResponder(nil)
    }

    // MARK: - Layout

    private func textWidth() -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let measured = (field.stringValue as NSString).size(withAttributes: attributes).width
        return ceil(max(minimumTextWidth, measured + 6))
    }

    private func resizeToFitText() {
        let width = textWidth()
        let boxHeight = inkHeight + verticalPadding * 2
        setFrameSize(NSSize(width: width + padding.left + padding.right, height: boxHeight))
        let fieldTopFromBottom = boxHeight - fieldTopOffset
        field.frame = CGRect(
            x: padding.left,
            y: fieldTopFromBottom - lineHeight,
            width: width,
            height: lineHeight
        )
        if let anchorBaseline {
            place(baseline: anchorBaseline, x: anchorX)
        }
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        path.lineWidth = 1
        NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
        path.stroke()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        resizeToFitText()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        onCommit?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }
        return false
    }
}
