import Foundation
import AppKit
import CoreGraphics
import Vision

enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法解析图片 / Invalid image"
        case .recognitionFailed(let message): return message
        }
    }
}

/// One recognized piece of text, with geometry in image pixel space (top-left origin).
struct OCRTextBlock: Identifiable, Equatable {
    let id: UUID
    let text: String
    let confidence: Double
    let pixelBox: CGRect
    let normalizedBox: CGRect

    init(id: UUID = UUID(), text: String, confidence: Double, pixelBox: CGRect, normalizedBox: CGRect) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.pixelBox = pixelBox
        self.normalizedBox = normalizedBox
    }
}

struct OCRResult {
    let blocks: [OCRTextBlock]
    let imageSize: CGSize
    /// Blocks grouped into visual lines, each line sorted left to right.
    let lines: [[OCRTextBlock]]

    var isEmpty: Bool { blocks.isEmpty }
    var blockCount: Int { blocks.count }

    /// Plain text, one visual line per output line.
    var plainText: String {
        lines
            .map { $0.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    /// Text that keeps the rough horizontal layout of the original image by padding gaps.
    var layoutText: String {
        lines.map { line -> String in
            guard let first = line.first else { return "" }
            var output = ""
            var cursor = first.normalizedBox.minX
            for block in line {
                let gap = block.normalizedBox.minX - cursor
                if gap > 0.012, !output.isEmpty {
                    output += String(repeating: " ", count: min(60, Int((gap / 0.008).rounded())))
                } else if !output.isEmpty {
                    output += " "
                }
                output += block.text
                cursor = block.normalizedBox.maxX
            }
            return output
        }
        .joined(separator: "\n")
    }

    static let empty = OCRResult(blocks: [], imageSize: .zero, lines: [])
}

/// Text recognition backed by the system Vision framework, mirroring the approach used by the
/// reference image-viewer project (VNRecognizeTextRequest with Chinese + English).
enum OCRService {
    static let defaultLanguages = ["zh-Hans", "zh-Hant", "en-US"]

    /// Every Vision request runs on this one serial queue: the pre-warm and the real request must
    /// never overlap, because concurrent calls to the recognizer occasionally fail with a transient
    /// TextRecognition error (CRImageReaderError) on a busy machine.
    private static let workQueue = DispatchQueue(label: "com.copyglass.ocr", qos: .userInitiated)
    private static let stateLock = NSLock()
    /// Transient failures are retried; three attempts covers the observed CRImageReaderError.
    private static let maximumAttempts = 3
    private static var didWarmUp = false
    private static var lastWarmUp = Date.distantPast

    /// Languages supported by the current revision, asked once and reused.
    private static let supportedLanguages: [String] = {
        (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate,
            revision: VNRecognizeTextRequest.currentRevision
        )) ?? []
    }()

    /// Loads the recognition models in the background. Safe to call often; repeats are skipped for
    /// two minutes so a capture session does not queue the work over and over.
    static func warmUpIfNeeded() {
        stateLock.lock()
        let now = Date()
        let shouldRun = !didWarmUp || now.timeIntervalSince(lastWarmUp) > 120
        if shouldRun {
            didWarmUp = true
            lastWarmUp = now
        }
        stateLock.unlock()
        guard shouldRun else { return }
        workQueue.async { performWarmUp() }
    }

    private static func performWarmUp() {
        guard let image = warmUpImage() else { return }
        let request = makeRequest(accurate: true, languageCorrection: true, languages: defaultLanguages)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        _ = try? handler.perform([request])
        stateLock.lock()
        lastWarmUp = Date()
        stateLock.unlock()
    }

    /// A tiny synthetic image with text, so the warm-up exercises the same pipeline as a real run.
    private static func warmUpImage() -> CGImage? {
        guard let context = ImageUtils.makeContext(width: 160, height: 44) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 44))
        guard let base = context.makeImage() else { return nil }
        let label = AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 8, y: 30)],
            color: AnnotationColor(red: 0, green: 0, blue: 0),
            lineWidth: 3,
            text: "Copy8 Glass"
        )
        return AnnotationRenderer.render(base: base, shapes: [label]) ?? base
    }

    private static func makeRequest(
        accurate: Bool,
        languageCorrection: Bool,
        languages: [String]
    ) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.usesLanguageCorrection = languageCorrection
        request.minimumTextHeight = 0.0

        let supported = supportedLanguages
        if !supported.isEmpty {
            let filtered = languages.filter { supported.contains($0) }
            request.recognitionLanguages = filtered.isEmpty ? Array(supported.prefix(3)) : filtered
        } else {
            request.recognitionLanguages = languages
        }
        return request
    }

    static func recognize(
        image: CGImage,
        languages: [String] = defaultLanguages,
        accurate: Bool = true,
        languageCorrection: Bool = true
    ) throws -> OCRResult {
        var lastError: Error?
        for attempt in 0..<maximumAttempts {
            do {
                return try recognizeOnce(
                    image: image,
                    languages: languages,
                    accurate: accurate,
                    languageCorrection: languageCorrection
                )
            } catch let error as OCRError {
                // Only transient recognition failures are worth another try.
                guard case .recognitionFailed = error else { throw error }
                lastError = error
                if attempt < maximumAttempts - 1 {
                    Thread.sleep(forTimeInterval: attempt == 0 ? 0.2 : 0.6)
                }
            }
        }
        throw lastError ?? OCRError.recognitionFailed(L10n.t(.ocrFailed, lang: AppLanguage.current))
    }

    private static func recognizeOnce(
        image: CGImage,
        languages: [String],
        accurate: Bool,
        languageCorrection: Bool
    ) throws -> OCRResult {
        guard image.width > 0, image.height > 0 else { throw OCRError.invalidImage }

        let request = makeRequest(
            accurate: accurate,
            languageCorrection: languageCorrection,
            languages: languages
        )

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        var blocks: [OCRTextBlock] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox
            // Vision uses a bottom-left normalized origin; convert to a top-left origin.
            let normalized = CGRect(
                x: box.minX,
                y: 1.0 - box.maxY,
                width: box.width,
                height: box.height
            )
            let pixel = CGRect(
                x: normalized.minX * width,
                y: normalized.minY * height,
                width: normalized.width * width,
                height: normalized.height * height
            )
            blocks.append(OCRTextBlock(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                pixelBox: pixel,
                normalizedBox: normalized
            ))
        }

        return OCRResult(blocks: blocks, imageSize: CGSize(width: width, height: height), lines: groupIntoLines(blocks))
    }

    static func recognizeAsync(
        image: CGImage,
        languages: [String] = defaultLanguages
    ) async -> Result<OCRResult, Error> {
        await withCheckedContinuation { continuation in
            workQueue.async {
                do {
                    let result = try recognize(image: image, languages: languages)
                    continuation.resume(returning: .success(result))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    /// Groups blocks that share a baseline into visual lines.
    static func groupIntoLines(_ blocks: [OCRTextBlock]) -> [[OCRTextBlock]] {
        let sorted = blocks.sorted { a, b in
            if abs(a.normalizedBox.midY - b.normalizedBox.midY) < 0.004 {
                return a.normalizedBox.minX < b.normalizedBox.minX
            }
            return a.normalizedBox.midY < b.normalizedBox.midY
        }

        var lines: [[OCRTextBlock]] = []
        for block in sorted {
            if let last = lines.last, !last.isEmpty {
                let reference = last.reduce(CGFloat(0)) { $0 + $1.normalizedBox.midY } / CGFloat(last.count)
                let averageHeight = last.reduce(CGFloat(0)) { $0 + $1.normalizedBox.height } / CGFloat(last.count)
                let threshold = max(0.008, averageHeight * 0.65)
                if abs(block.normalizedBox.midY - reference) <= threshold {
                    lines[lines.count - 1].append(block)
                    continue
                }
            }
            lines.append([block])
        }

        return lines.map { line in
            line.sorted { $0.normalizedBox.minX < $1.normalizedBox.minX }
        }
    }
}
