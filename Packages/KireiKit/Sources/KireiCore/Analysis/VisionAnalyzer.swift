#if canImport(Vision)
import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Bildanalyse mit Apples Vision, auf iPhone, iPad und Mac gleich.
///
/// Feature Print und Ästhetik-Score für jedes Foto, Gesichter nur für Fotos
/// in Gruppen. Alles läuft auf dem Gerät.
public struct VisionAnalyzer: ImageAnalyzer {
    /// Version 1: Feature Print Revision 2, Ästhetik-Score, Laplace-Schärfe.
    public let version = 1

    /// Gesichter schmaler als dieser Anteil der Bildbreite zählen nicht,
    /// etwa Menschen im Hintergrund.
    static let minimumFaceWidth: CGFloat = 0.08

    public init() {}

    public func analyze(_ thumbnail: Thumbnail) async throws -> ImageAnalysis {
        let handler = VNImageRequestHandler(
            cgImage: thumbnail.cgImage,
            orientation: thumbnail.orientation,
            options: [:]
        )

        // Feste Revision, damit Abstände über Systemupdates vergleichbar bleiben.
        let featureRequest = VNGenerateImageFeaturePrintRequest()
        featureRequest.revision = VNGenerateImageFeaturePrintRequestRevision2
        try handler.perform([featureRequest])
        let featurePrint = featureRequest.results?.first.flatMap(Self.featurePrint(from:))

        // Der Ästhetik-Score darf fehlen, ohne dass die ganze Analyse scheitert.
        let aestheticsRequest = VNCalculateImageAestheticsScoresRequest()
        try? handler.perform([aestheticsRequest])
        let aesthetics = aestheticsRequest.results?.first

        return ImageAnalysis(
            featurePrint: featurePrint,
            aestheticScore: aesthetics?.overallScore,
            isUtility: aesthetics?.isUtility ?? false,
            sharpness: SharpnessMeter.measure(thumbnail.cgImage)
        )
    }

    public func analyzeFaces(_ thumbnail: Thumbnail) async throws -> FaceSummary {
        let handler = VNImageRequestHandler(
            cgImage: thumbnail.cgImage,
            orientation: thumbnail.orientation,
            options: [:]
        )

        let landmarksRequest = VNDetectFaceLandmarksRequest()
        try handler.perform([landmarksRequest])
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        try? handler.perform([qualityRequest])

        let imageSize = thumbnail.orientedSize
        let faces = (landmarksRequest.results ?? [])
            .filter { $0.boundingBox.width >= Self.minimumFaceWidth }
        let openness = faces.compactMap { Self.eyeOpenness(of: $0, imageSize: imageSize) }
        let qualities = (qualityRequest.results ?? [])
            .filter { $0.boundingBox.width >= Self.minimumFaceWidth }
            .compactMap(\.faceCaptureQuality)

        return FaceSummary(
            faceCount: faces.count,
            minEyeOpenness: openness.min(),
            meanCaptureQuality: qualities.isEmpty
                ? nil
                : Double(qualities.reduce(0, +)) / Double(qualities.count)
        )
    }

    // MARK: Hilfen

    static func featurePrint(from observation: VNFeaturePrintObservation) -> FeaturePrint? {
        let count = observation.elementCount
        let data = observation.data
        guard count > 0 else { return nil }

        switch observation.elementType {
        case .float:
            guard data.count >= count * MemoryLayout<Float>.size else { return nil }
            let vector = data.withUnsafeBytes { raw in
                (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self) }
            }
            return FeaturePrint(vector: vector)
        case .double:
            guard data.count >= count * MemoryLayout<Double>.size else { return nil }
            let vector = data.withUnsafeBytes { raw in
                (0..<count).map { Float(raw.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Double>.size, as: Double.self)) }
            }
            return FeaturePrint(vector: vector)
        default:
            return nil
        }
    }

    /// Mittel aus linkem und rechtem Auge eines Gesichts.
    static func eyeOpenness(of face: VNFaceObservation, imageSize: CGSize) -> Double? {
        guard let landmarks = face.landmarks else { return nil }
        let eyes = [landmarks.leftEye, landmarks.rightEye].compactMap { $0 }
        let ratios = eyes.compactMap { EyeOpenness.ratio($0.pointsInImage(imageSize: imageSize)) }
        guard !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }
}
#endif
