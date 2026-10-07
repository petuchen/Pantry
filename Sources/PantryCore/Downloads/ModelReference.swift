import Foundation

/// Liberal input parsing (Postel's Law): accept what people actually paste —
/// bare names, `ollama run …` commands, and web URLs — and normalise it.
public enum ModelReference {
    private static let ollamaPattern = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9][A-Za-z0-9._\-/]*(?::[A-Za-z0-9._\-]+)?$"#, options: [])
    private static let repoPattern = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9][A-Za-z0-9._\-]*/[A-Za-z0-9][A-Za-z0-9._\-]*$"#, options: [])

    /// "ollama run llama3.2" | "https://ollama.com/library/llama3.2:3b" | "llama3.2:3b" -> "llama3.2:3b"
    public static func ollamaName(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["ollama run ", "ollama pull "] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        for prefix in ["https://ollama.com/library/", "http://ollama.com/library/", "https://ollama.com/", "http://ollama.com/"]
        where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        return matches(ollamaPattern, text) ? text : nil
    }

    /// "hf download org/name" | "https://huggingface.co/org/name/tree/main" | "org/name:Q4_K_M" -> "org/name"
    public static func huggingFaceRepo(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["hf download ", "huggingface-cli download "] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if let firstWord = text.split(separator: " ").first { text = String(firstWord) }
        }
        let lower = text.lowercased()
        for scheme in ["https://", "http://"] where lower.hasPrefix(scheme) {
            text = String(text.dropFirst(scheme.count))
        }
        for host in ["huggingface.co/", "hf.co/"] where text.lowercased().hasPrefix(host) {
            text = String(text.dropFirst(host.count))
            let parts = text.split(separator: "/").map(String.init)
            if let first = parts.first, ["datasets", "spaces"].contains(first) { return nil }
            text = parts.prefix(2).joined(separator: "/")
        }
        if let colon = text.firstIndex(of: ":") { text = String(text[text.startIndex..<colon]) }
        return matches(repoPattern, text) ? text : nil
    }

    private static func matches(_ pattern: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(location: 0, length: (value as NSString).length)
        return pattern.firstMatch(in: value, options: [], range: range) != nil
    }
}
