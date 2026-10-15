import CoreGraphics
import Foundation
import Testing
@testable import KireiCore

@Suite("Merkmalsvektor")
struct FeaturePrintTests {
    @Test("8 Bit verändern den Abstand kaum")
    func quantizationKeepsDistances() {
        var generator = SplitMix(seed: 7)
        for _ in 0..<20 {
            let a = normalized((0..<768).map { _ in generator.nextFloat() - 0.5 })
            let b = normalized((0..<768).map { _ in generator.nextFloat() - 0.5 })
            let exact = euclidean(a, b)
            let quantized = FeaturePrint(vector: a).distance(to: FeaturePrint(vector: b))
            #expect(abs(exact - quantized) < 0.02)
        }
    }

    @Test("Speichern und Laden ergibt denselben Vektor")
    func dataRoundTrip() throws {
        let print = FeaturePrint(vector: [0.5, -0.25, 0.125, -1, 0])
        let restored = try #require(FeaturePrint(data: print.data))
        #expect(restored == print)
        #expect(print.data.count == 4 + 5)
    }

    @Test("Abstand zu sich selbst ist null, verschiedene Längen sind unvergleichbar")
    func edgeCases() {
        let print = testPrint(axis: 2)
        #expect(print.distance(to: print) == 0)
        #expect(print.distance(to: testPrint(axis: 2, dimensions: 4)) == .infinity)
        #expect(FeaturePrint(data: Data([1, 2])) == nil)
    }

    private func normalized(_ vector: [Float]) -> [Float] {
        let length = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        return vector.map { $0 / length }
    }

    private func euclidean(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(Float(0)) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
    }
}

@Suite("Schärfe")
struct SharpnessTests {
    @Test("Harte Kanten sind schärfer als ein weicher Verlauf")
    func checkerboardIsSharper() {
        let sharp = SharpnessMeter.measure(TestImages.checkerboard())
        let soft = SharpnessMeter.measure(TestImages.gradient())
        #expect(sharp > 1_000)
        #expect(soft < 10)
    }

    @Test("Einfarbige Fläche hat keine Schärfe")
    func flatImage() {
        #expect(SharpnessMeter.measure(TestImages.marker(width: 64)) == 0)
    }
}

@Suite("Augenöffnung")
struct EyeOpennessTests {
    /// Umriss eines Auges als Ellipse, wie Vision ihn mit 8 Punkten liefert.
    private func eye(width: Double, height: Double, angle: Double = 0) -> [CGPoint] {
        (0..<8).map { step in
            let t = Double(step) / 8 * 2 * Double.pi
            let x = cos(t) * width / 2
            let y = sin(t) * height / 2
            return CGPoint(
                x: 100 + x * cos(angle) - y * sin(angle),
                y: 100 + x * sin(angle) + y * cos(angle)
            )
        }
    }

    @Test("Offenes Auge hat ein höheres Verhältnis als ein geschlossenes")
    func openVersusClosed() throws {
        let open = try #require(EyeOpenness.ratio(eye(width: 30, height: 10)))
        let closed = try #require(EyeOpenness.ratio(eye(width: 30, height: 1.5)))
        #expect(open > 0.3)
        #expect(closed < 0.1)
    }

    @Test("Ein schräger Kopf verfälscht nichts")
    func rotationInvariant() throws {
        let straight = try #require(EyeOpenness.ratio(eye(width: 30, height: 10)))
        let tilted = try #require(EyeOpenness.ratio(eye(width: 30, height: 10, angle: 0.6)))
        #expect(abs(straight - tilted) < 0.02)
    }

    @Test("Zu wenige Punkte geben kein Ergebnis")
    func tooFewPoints() {
        #expect(EyeOpenness.ratio([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]) == nil)
    }
}

@Suite("Größe schätzen")
struct SizeEstimatorTests {
    @Test("Eine Minute 4K liegt bei etwa 170 MB, 1080p bei 60 MB")
    func videoEstimates() {
        let fourK = AssetRecord(id: AssetID("a"), kind: .video, pixelWidth: 3840, pixelHeight: 2160, duration: 60)
        let fullHD = AssetRecord(id: AssetID("b"), kind: .video, pixelWidth: 1920, pixelHeight: 1080, duration: 60)
        #expect(abs(Double(SizeEstimator.estimatedBytes(for: fourK)) - 170_000_000) < 5_000_000)
        #expect(abs(Double(SizeEstimator.estimatedBytes(for: fullHD)) - 60_000_000) < 1_000_000)
    }

    @Test("Live Photos sind größer als normale Fotos")
    func livePhoto() {
        let still = AssetRecord(id: AssetID("a"), kind: .photo, pixelWidth: 4032, pixelHeight: 3024)
        let live = AssetRecord(id: AssetID("b"), kind: .photo, traits: .livePhoto, pixelWidth: 4032, pixelHeight: 3024)
        #expect(SizeEstimator.estimatedBytes(for: live) > SizeEstimator.estimatedBytes(for: still))
    }
}

/// Kleiner, reproduzierbarer Zufallsgenerator für Tests.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}
