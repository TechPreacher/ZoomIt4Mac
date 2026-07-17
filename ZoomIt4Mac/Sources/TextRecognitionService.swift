import Vision

/// On-device text recognition for OCR snip. Runs Vision locally on the
/// already-captured snapshot crop — no network, no additional permissions.
enum TextRecognitionService {
    /// Recognizes text in the image and delivers the recognized lines
    /// (Vision's natural top-to-bottom order) on the main actor. Empty
    /// array on error or when nothing is recognized.
    static func recognizeText(in image: CGImage, completion: @escaping @MainActor @Sendable ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            let lines: [String]
            do {
                try handler.perform([request])
                lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            } catch {
                NSLog("text recognition failed: \(error)")
                lines = []
            }
            Task { @MainActor in
                completion(lines)
            }
        }
    }
}
