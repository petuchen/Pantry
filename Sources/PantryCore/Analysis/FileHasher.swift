import Foundation
import CryptoKit

public enum FileHasher {
    /// Streaming SHA-256 so multi-gigabyte weights never have to fit in memory.
    public static func sha256Hex(of url: URL, chunkSize: Int = 8 * 1024 * 1024) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
