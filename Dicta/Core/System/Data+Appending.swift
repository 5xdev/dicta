import Foundation

extension Data {
    mutating func append(_ string: String) { append(Data(string.utf8)) }

    /// Appends the little-endian bytes of a fixed-width integer (WAV headers are little-endian throughout).
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
