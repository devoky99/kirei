import Foundation

/// Merkmalsvektor eines Bildes, platzsparend mit 8 Bit pro Wert gespeichert.
///
/// Vision liefert 768 Kommazahlen (3 KB). Gespeichert werden ein Faktor und
/// 768 ganze Zahlen von -127 bis 127 (772 Byte). Der Abstand zweier Bilder
/// ändert sich dadurch nur um etwa ein Hundertstel, die Schwellen liegen
/// zehnmal höher.
public struct FeaturePrint: Sendable, Equatable {
    public let scale: Float
    public let values: [Int8]

    public init(scale: Float, values: [Int8]) {
        self.scale = scale
        self.values = values
    }

    /// Quantisiert einen Vektor auf 8 Bit pro Wert.
    public init(vector: [Float]) {
        let maxMagnitude = vector.reduce(Float(0)) { max($0, abs($1)) }
        let scale = maxMagnitude > 0 ? maxMagnitude / 127 : 1
        self.scale = scale
        self.values = vector.map { value in
            Int8(clamping: Int((value / scale).rounded()))
        }
    }

    /// Der Vektor als Kommazahlen, mit kleinem Rundungsfehler.
    public var vector: [Float] {
        values.map { Float($0) * scale }
    }

    /// Euklidischer Abstand. 0 heißt gleich, bei Vision Revision 2 liegen
    /// sehr verschiedene Bilder um 1,0 bis 1,4.
    public func distance(to other: FeaturePrint) -> Float {
        guard values.count == other.values.count, !values.isEmpty else { return .infinity }
        var sum: Float = 0
        for index in values.indices {
            let difference = Float(values[index]) * scale - Float(other.values[index]) * other.scale
            sum += difference * difference
        }
        return sum.squareRoot()
    }

    // MARK: Speichern

    /// Vier Byte Faktor, danach ein Byte pro Wert.
    public var data: Data {
        var result = Data(capacity: 4 + values.count)
        let bits = scale.bitPattern
        for shift in stride(from: 0, to: 32, by: 8) {
            result.append(UInt8(truncatingIfNeeded: bits >> UInt32(shift)))
        }
        for value in values {
            result.append(UInt8(bitPattern: value))
        }
        return result
    }

    public init?(data: Data) {
        guard data.count > 4 else { return nil }
        let bytes = [UInt8](data)
        var bits: UInt32 = 0
        for index in 0..<4 {
            bits |= UInt32(bytes[index]) << UInt32(8 * index)
        }
        self.scale = Float(bitPattern: bits)
        self.values = bytes[4...].map { Int8(bitPattern: $0) }
    }
}
