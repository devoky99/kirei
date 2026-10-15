import Darwin

/// Höchster Speicherbedarf des Prozesses, für das Ziel „unter 300 MB“.
enum MemoryUsage {
    /// Spitzenwert seit Prozessstart (resident set size), in Byte.
    static func peakResidentBytes() -> Int64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        // Auf Apple-Systemen in Byte, nicht in Kilobyte.
        return Int64(usage.ru_maxrss)
    }
}
