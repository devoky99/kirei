import Foundation

/// Wie viel gleichzeitig analysiert wird, abhängig vom Zustand des Geräts.
///
/// Wird das Gerät warm oder ist der Stromsparmodus an, rechnet Kirei
/// langsamer. Bei kritischer Temperatur pausiert die Analyse.
enum AnalysisThrottle {
    static func currentParallelism(processInfo: ProcessInfo = .processInfo) -> Int {
        switch processInfo.thermalState {
        case .critical:
            return 0
        case .serious:
            return 1
        default:
            break
        }
        if processInfo.isLowPowerModeEnabled {
            return 1
        }
        #if os(macOS)
        return 4
        #else
        return 2
        #endif
    }

    /// Wartet, bis wieder gerechnet werden darf, und sagt, wie viel parallel geht.
    static func waitForCapacity() async throws -> Int {
        while true {
            let parallelism = currentParallelism()
            if parallelism > 0 {
                return parallelism
            }
            try await Task.sleep(for: .seconds(10))
        }
    }
}

extension Array {
    /// Teilt in Stücke fester Größe, das letzte kann kürzer sein.
    func chunks(of size: Int) -> [ArraySlice<Element>] {
        guard size > 0 else { return [self[...]] }
        return stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
