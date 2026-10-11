import Foundation

/// 간단한 `.env` 파서.
///
/// 지원 형식:
/// - `KEY=value`, `export KEY=value`
/// - `#` 주석 줄, 값 뒤의 ` # 주석`
/// - 큰따옴표 값(`\n`, `\"`, `\\` 이스케이프), 작은따옴표 값(그대로)
public enum EnvFile {
    public static func parse(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else { continue }
            let rawValue = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            values[key] = parseValue(rawValue)
        }
        return values
    }

    public static func load(from url: URL) throws -> [String: String] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return parse(contents)
    }

    /// 값 하나를 바꾼 내용을 돌려준다. 다른 줄과 주석은 그대로 둔다.
    ///
    /// - 이미 `KEY=…` 줄이 있으면 그 줄을 바꾼다.
    /// - 없고 `# KEY=…` 처럼 주석 처리된 예시 줄이 있으면 그 자리에 쓴다 (설명 주석 바로 아래에 남도록).
    /// - 둘 다 없으면 끝에 덧붙인다.
    /// - `value` 가 nil 이면 설정을 지운다 (줄을 주석으로 바꾼다).
    public static func updating(_ contents: String, key: String, value: String?) -> String {
        var lines = contents.components(separatedBy: "\n")
        let hadTrailingNewline = lines.last == ""
        if hadTrailingNewline { lines.removeLast() }

        func assignedKey(_ line: String) -> String? {
            var text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("export ") { text = String(text.dropFirst("export ".count)) }
            guard let equals = text.firstIndex(of: "=") else { return nil }
            return text[..<equals].trimmingCharacters(in: .whitespaces)
        }
        func commentedKey(_ line: String) -> String? {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("#") else { return nil }
            return assignedKey(String(text.drop(while: { $0 == "#" || $0 == " " })))
        }

        let active = lines.indices.filter { !lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("#") && assignedKey(lines[$0]) == key }
        let newLine = value.map { "\(key)=\(formatValue($0))" }

        if let last = active.last {
            if let newLine {
                lines[last] = newLine
            } else {
                lines[last] = "# " + lines[last]
            }
            // 같은 키가 여러 번 있으면 마지막 값이 쓰이므로 앞의 것들은 지워 혼동을 막는다.
            for index in active.dropLast().reversed() { lines.remove(at: index) }
        } else if let newLine {
            if let example = lines.indices.last(where: { commentedKey(lines[$0]) == key }) {
                lines[example] = newLine
            } else {
                lines.append(newLine)
            }
        }
        return lines.joined(separator: "\n") + (hadTrailingNewline || !lines.isEmpty ? "\n" : "")
    }

    /// 공백·`#`·따옴표가 들어간 값은 큰따옴표로 감싼다.
    static func formatValue(_ value: String) -> String {
        let needsQuotes = value.isEmpty || value.contains(where: { $0 == " " || $0 == "\t" || $0 == "#" || $0 == "\"" || $0 == "'" || $0 == "\\" })
        guard needsQuotes else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    static func isValidKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first)
        else { return false }
        return key.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && CharacterSet.alphanumerics.contains($0)) }
    }

    static func parseValue(_ raw: String) -> String {
        if raw.hasPrefix("\"") {
            var result = ""
            var escaping = false
            for character in raw.dropFirst() {
                if escaping {
                    switch character {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    default: result.append(character)
                    }
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    return result
                } else {
                    result.append(character)
                }
            }
            return result
        }
        if raw.hasPrefix("'") {
            let body = raw.dropFirst()
            if let end = body.firstIndex(of: "'") {
                return String(body[..<end])
            }
            return String(body)
        }
        // 따옴표 없는 값: 공백 뒤의 # 부터는 주석으로 본다.
        if let commentRange = raw.range(of: " #") ?? raw.range(of: "\t#") {
            return raw[..<commentRange.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        return raw
    }
}
