import Foundation

struct ConfigTOMLParser: Sendable {
  let path: String

  func parse(_ input: String) throws -> ParsedConfigFile {
    var parsed = ParsedConfigFile()
    var currentSection: String?
    var seenSections = Set<String>()
    var seenKeys = Set<String>()

    for (offset, rawLine) in input.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      let lineNumber = offset + 1
      let line = String(rawLine)
      let stripped = try stripComment(from: line, lineNumber: lineNumber)
      let trimmed = stripped.trimmingCharacters(in: .whitespaces)

      if trimmed.isEmpty {
        continue
      }

      if trimmed.hasPrefix("[") {
        let section = try parseSection(trimmed, line: line, lineNumber: lineNumber)
        guard ConfigSchema.sections.contains(section) else {
          throw parseError(line: lineNumber, column: firstContentColumn(in: line), "Unknown config section '\(section)'")
        }
        guard !seenSections.contains(section) else {
          throw parseError(line: lineNumber, column: firstContentColumn(in: line), "Duplicate config section '\(section)'")
        }
        currentSection = section
        seenSections.insert(section)
        parsed.values[section] = [:]
        continue
      }

      guard let section = currentSection else {
        throw parseError(line: lineNumber, column: firstContentColumn(in: line), "Config key appears before any section")
      }

      let assignment = try parseAssignment(trimmed, line: line, lineNumber: lineNumber)
      guard ConfigSchema.isKnown(section: section, key: assignment.key) else {
        throw parseError(line: lineNumber, column: assignment.keyColumn, "Unknown config key '\(section).\(assignment.key)'")
      }

      let keyIdentity = "\(section).\(assignment.key)"
      guard !seenKeys.contains(keyIdentity) else {
        throw parseError(line: lineNumber, column: assignment.keyColumn, "Duplicate config key '\(section).\(assignment.key)'")
      }

      let scalar = try parseScalar(assignment.value, lineNumber: lineNumber, column: assignment.valueColumn)
      try validateScalarType(
        scalar,
        section: section,
        key: assignment.key,
        lineNumber: lineNumber,
        column: assignment.valueColumn
      )
      parsed.values[section, default: [:]][assignment.key] = scalar
      seenKeys.insert(keyIdentity)
    }

    return parsed
  }

  private func parseSection(_ trimmed: String, line: String, lineNumber: Int) throws -> String {
    guard trimmed.hasSuffix("]"), trimmed.filter({ $0 == "[" }).count == 1, trimmed.filter({ $0 == "]" }).count == 1 else {
      throw parseError(line: lineNumber, column: firstContentColumn(in: line), "Malformed config section")
    }
    let name = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty, !name.contains("."), !name.contains(" ") else {
      throw parseError(line: lineNumber, column: firstContentColumn(in: line), "Malformed config section")
    }
    return name
  }

  private func parseAssignment(_ trimmed: String, line: String, lineNumber: Int) throws -> ConfigAssignment {
    guard let equalIndex = trimmed.firstIndex(of: "=") else {
      throw parseError(line: lineNumber, column: firstContentColumn(in: line), "Expected key = value assignment")
    }

    let keyPart = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
    let valuePart = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)

    guard !keyPart.isEmpty, !keyPart.contains(".") else {
      throw parseError(line: lineNumber, column: firstContentColumn(in: line), "Malformed config key")
    }
    guard !valuePart.isEmpty else {
      let valueColumn = (line.firstIndex(of: "=").map { line.distance(from: line.startIndex, to: $0) } ?? 0) + 2
      throw parseError(line: lineNumber, column: valueColumn, "Missing config value")
    }

    let keyColumn = (line.range(of: keyPart).map { line.distance(from: line.startIndex, to: $0.lowerBound) } ?? 0) + 1
    let valueColumn = (line.range(of: valuePart).map { line.distance(from: line.startIndex, to: $0.lowerBound) } ?? 0) + 1
    return ConfigAssignment(key: keyPart, value: valuePart, keyColumn: keyColumn, valueColumn: valueColumn)
  }

  private func parseScalar(_ value: String, lineNumber: Int, column: Int) throws -> ConfigScalar {
    if value.hasPrefix("\"") {
      return .string(try parseString(value, lineNumber: lineNumber, column: column))
    }
    if value == "true" {
      return .boolean(true)
    }
    if value == "false" {
      return .boolean(false)
    }
    if value.hasPrefix("[") || value.hasPrefix("{") {
      throw parseError(line: lineNumber, column: column, "Unsupported config value type")
    }
    if let integer = Int(value) {
      return .integer(integer)
    }
    throw parseError(line: lineNumber, column: column, "Malformed config value")
  }

  private func parseString(_ value: String, lineNumber: Int, column: Int) throws -> String {
    guard value.count >= 2, value.hasSuffix("\"") else {
      throw parseError(line: lineNumber, column: column, "Unterminated string value")
    }

    let body = value.dropFirst().dropLast()
    var output = ""
    var escaping = false
    for character in body {
      if escaping {
        switch character {
        case "\"", "\\":
          output.append(character)
        case "n":
          output.append("\n")
        case "t":
          output.append("\t")
        default:
          throw parseError(line: lineNumber, column: column, "Unsupported string escape")
        }
        escaping = false
      } else if character == "\\" {
        escaping = true
      } else {
        output.append(character)
      }
    }

    if escaping {
      throw parseError(line: lineNumber, column: column, "Unterminated string escape")
    }
    return output
  }

  private func validateScalarType(
    _ scalar: ConfigScalar,
    section: String,
    key: String,
    lineNumber: Int,
    column: Int
  ) throws {
    guard let expected = ConfigSchema.expectedType(section: section, key: key) else {
      return
    }

    let isValid = switch (expected, scalar) {
    case (.string, .string),
         (.integer, .integer),
         (.boolean, .boolean):
      true
    default:
      false
    }

    if !isValid {
      throw parseError(
        line: lineNumber,
        column: column,
        "Config key '\(section).\(key)' expects \(expected.description)"
      )
    }
  }

  private func stripComment(from line: String, lineNumber: Int) throws -> String {
    var output = ""
    var insideString = false
    var escaping = false

    for character in line {
      if escaping {
        output.append(character)
        escaping = false
        continue
      }

      if character == "\\" && insideString {
        output.append(character)
        escaping = true
        continue
      }

      if character == "\"" {
        insideString.toggle()
        output.append(character)
        continue
      }

      if character == "#", !insideString {
        return output
      }

      output.append(character)
    }

    if insideString {
      throw parseError(line: lineNumber, column: max(output.count, 1), "Unterminated string value")
    }
    return output
  }

  private func firstContentColumn(in line: String) -> Int {
    if let index = line.firstIndex(where: { !$0.isWhitespace }) {
      return line.distance(from: line.startIndex, to: index) + 1
    }
    return 1
  }

  private func parseError(line: Int, column: Int, _ message: String) -> AppleGatewayConfigError {
    .parse(path: path, line: line, column: column, message: message)
  }
}

private struct ConfigAssignment {
  var key: String
  var value: String
  var keyColumn: Int
  var valueColumn: Int
}
