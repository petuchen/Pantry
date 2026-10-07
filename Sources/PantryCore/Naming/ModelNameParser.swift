import Foundation

public struct ParsedModelName: Equatable, Sendable {
    /// Lowercased family + version with separators, size, quantization and variant tokens removed.
    /// "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf" and "llama3.1:8b" both give "llama3.1".
    public var baseKey: String
    /// Original token, upper-cased, e.g. "8B".
    public var parameterLabel: String?
    public var parameterBillions: Double?
    /// "Q4_K_M", "4-bit", "BF16" ...
    public var quantization: String?
    /// true = instruct/chat/it, false = base/pt, nil = not stated.
    public var isInstruct: Bool?
}

public enum ParameterSize {
    /// "7B" -> 7, "270M" -> 0.27, "8x7B" -> 56, "E2B" -> 2.
    public static func billions(from label: String) -> Double? {
        let s = label.lowercased().trimmingCharacters(in: .whitespaces)
        guard let last = s.last, last == "b" || last == "m" else { return nil }
        var body = String(s.dropLast())
        if body.hasPrefix("e") { body.removeFirst() }
        var factor = 1.0
        if let xIndex = body.firstIndex(of: "x") {
            guard let multiplier = Double(String(body[body.startIndex..<xIndex])) else { return nil }
            factor = multiplier
            body = String(body[body.index(after: xIndex)...])
        }
        guard let value = Double(body) else { return nil }
        let billions = value * factor
        return last == "m" ? billions / 1000.0 : billions
    }

    /// Runtimes report parameter counts differently ("3.2B" vs "3B", "7.6B" vs "7B"),
    /// so sizes within 20% are treated as the same size.
    public static func areClose(_ a: Double, _ b: Double, tolerance: Double = 0.2) -> Bool {
        let high = max(a, b)
        guard high > 0 else { return false }
        return abs(a - b) / high <= tolerance
    }
}

public enum ModelNameParser {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants covered by unit tests.
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    private static let quantPatterns: [NSRegularExpression] = [
        regex(#"(?<![a-z0-9])(iq[1-4]_(?:xxs|xs|xl|nl|s|m)|q[2-8]_(?:k_(?:xl|[sml])|k|[01]))(?![a-z0-9])"#),
        regex(#"(?<![a-z0-9])(\d{1,2}-?bit)(?![a-z0-9])"#),
        regex(#"(?<![a-z0-9])(bf16|fp16|f16|fp32|f32|fp8|int8|int4|mxfp4|nvfp4)(?![a-z0-9])"#),
    ]
    private static let shardPattern = regex(#"-\d{5}-of-\d{5}$"#)
    private static let parameterPattern = regex(#"^(?:\d+x)?\d+(?:\.\d+)?[bm]$|^e\d+b$"#)
    private static let activeParameterPattern = regex(#"^a\d+(?:\.\d+)?b$"#)
    private static let bitsPattern = regex(#"^\d+-?bit$"#)

    private static let noiseTokens: Set<String> = [
        "meta", "gguf", "mlx", "awq", "gptq", "hf", "latest", "ud", "community", "imatrix", "i1",
    ]
    private static let instructTokens: Set<String> = ["instruct", "it", "chat"]
    private static let baseTokens: Set<String> = ["base", "pt"]

    public static func parse(_ raw: String) -> ParsedModelName {
        var s = raw.lowercased()
        if let slash = s.lastIndex(of: "/") {
            s = String(s[s.index(after: slash)...])
        }
        if s.hasSuffix(".gguf") { s = String(s.dropLast(5)) }
        s = replacing(shardPattern, in: s, with: "")

        var quantization: String?
        for pattern in quantPatterns {
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = pattern.firstMatch(in: s, options: [], range: range) {
                quantization = normalizeQuantization(ns.substring(with: match.range(at: 1)))
                s = ns.replacingCharacters(in: match.range, with: " ")
                break
            }
        }

        let tokens: [String] = s
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == ".") })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }

        var parameterToken: String?
        var isInstruct: Bool?
        var kept: [String] = []
        for token in tokens {
            if matches(activeParameterPattern, token) { continue }
            if let parameterToken, token == parameterToken { continue }
            if parameterToken == nil, matches(parameterPattern, token) {
                parameterToken = token
                continue
            }
            if noiseTokens.contains(token) { continue }
            if instructTokens.contains(token) { isInstruct = true; continue }
            if baseTokens.contains(token) {
                if isInstruct == nil { isInstruct = false }
                continue
            }
            kept.append(token)
        }

        return ParsedModelName(
            baseKey: kept.joined(),
            parameterLabel: parameterToken?.uppercased(),
            parameterBillions: parameterToken.flatMap { ParameterSize.billions(from: $0) },
            quantization: quantization,
            isInstruct: isInstruct
        )
    }

    private static func normalizeQuantization(_ value: String) -> String {
        if matches(bitsPattern, value) {
            let digits = value.filter { $0.isNumber }
            return digits + "-bit"
        }
        return value.uppercased()
    }

    private static func matches(_ pattern: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(location: 0, length: (value as NSString).length)
        return pattern.firstMatch(in: value, options: [], range: range) != nil
    }

    private static func replacing(_ pattern: NSRegularExpression, in value: String, with template: String) -> String {
        let range = NSRange(location: 0, length: (value as NSString).length)
        return pattern.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: template)
    }
}
