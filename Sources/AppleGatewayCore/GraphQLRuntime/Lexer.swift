import Foundation

struct GraphQLToken: Equatable {
  enum Kind: Equatable {
    case name(String)
    case int(String)
    case float(String)
    case string(String)
    case punctuator(String)
    case end
  }

  var kind: Kind
  var location: GraphQLLocation
}

struct GraphQLLexer {
  private let characters: [Character]
  private var index = 0
  private var line = 1
  private var column = 1

  init(_ source: String) {
    characters = Array(source)
  }

  mutating func lex() throws -> [GraphQLToken] {
    var tokens: [GraphQLToken] = []

    while let character = peek() {
      if character == "#" {
        skipComment()
      } else if character.isGraphQLWhitespace {
        advance()
      } else if character.isGraphQLNameStart {
        tokens.append(readName())
      } else if character == "\"" {
        tokens.append(try readString())
      } else if character == "-" || character.isNumber {
        tokens.append(try readNumber())
      } else {
        tokens.append(try readPunctuator())
      }
    }

    tokens.append(GraphQLToken(kind: .end, location: currentLocation))
    return tokens
  }

  private var currentLocation: GraphQLLocation {
    GraphQLLocation(line: line, column: column)
  }

  private func peek(offset: Int = 0) -> Character? {
    let target = index + offset
    guard target < characters.count else {
      return nil
    }
    return characters[target]
  }

  @discardableResult
  private mutating func advance() -> Character? {
    guard index < characters.count else {
      return nil
    }

    let character = characters[index]
    index += 1
    if character == "\n" {
      line += 1
      column = 1
    } else {
      column += 1
    }
    return character
  }

  private mutating func skipComment() {
    while let character = peek(), character != "\n" {
      advance()
    }
  }

  private mutating func readName() -> GraphQLToken {
    let location = currentLocation
    var value = ""
    while let character = peek(), character.isGraphQLNameContinue {
      value.append(character)
      advance()
    }
    return GraphQLToken(kind: .name(value), location: location)
  }

  private mutating func readString() throws -> GraphQLToken {
    let location = currentLocation
    advance()
    var value = ""

    while let character = peek() {
      if character == "\"" {
        advance()
        return GraphQLToken(kind: .string(value), location: location)
      }

      if character == "\n" {
        throw GraphQLRuntimeError(
          message: "Unterminated string literal",
          location: currentLocation,
          code: .graphQLParseError
        )
      }

      if character == "\\" {
        advance()
        guard let escaped = peek() else {
          throw GraphQLRuntimeError(
            message: "Unterminated string escape",
            location: currentLocation,
            code: .graphQLParseError
          )
        }
        value.append(try decodeEscape(escaped, location: currentLocation))
        advance()
      } else {
        value.append(character)
        advance()
      }
    }

    throw GraphQLRuntimeError(
      message: "Unterminated string literal",
      location: location,
      code: .graphQLParseError
    )
  }

  private func decodeEscape(_ character: Character, location: GraphQLLocation) throws -> Character {
    switch character {
    case "\"": return "\""
    case "\\": return "\\"
    case "/": return "/"
    case "b": return "\u{8}"
    case "f": return "\u{c}"
    case "n": return "\n"
    case "r": return "\r"
    case "t": return "\t"
    default:
      throw GraphQLRuntimeError(
        message: "Unsupported string escape \\(character)",
        location: location,
        code: .graphQLParseError
      )
    }
  }

  private mutating func readNumber() throws -> GraphQLToken {
    let location = currentLocation
    var value = ""
    var isFloat = false

    if peek() == "-" {
      value.append("-")
      advance()
    }

    guard let firstDigit = peek(), firstDigit.isNumber else {
      throw GraphQLRuntimeError(
        message: "Expected digit after '-'",
        location: currentLocation,
        code: .graphQLParseError
      )
    }

    while let character = peek(), character.isNumber {
      value.append(character)
      advance()
    }

    if peek() == "." {
      isFloat = true
      value.append(".")
      advance()
      guard let character = peek(), character.isNumber else {
        throw GraphQLRuntimeError(
          message: "Expected digit after decimal point",
          location: currentLocation,
          code: .graphQLParseError
        )
      }
      while let character = peek(), character.isNumber {
        value.append(character)
        advance()
      }
    }

    return GraphQLToken(kind: isFloat ? .float(value) : .int(value), location: location)
  }

  private mutating func readPunctuator() throws -> GraphQLToken {
    let location = currentLocation

    if peek() == ".", peek(offset: 1) == ".", peek(offset: 2) == "." {
      advance()
      advance()
      advance()
      return GraphQLToken(kind: .punctuator("..."), location: location)
    }

    guard let character = peek(), "{}():![]=@$,".contains(character) else {
      throw GraphQLRuntimeError(
        message: "Unexpected character '\(peek() ?? "?")'",
        location: location,
        code: .graphQLParseError
      )
    }

    advance()
    return GraphQLToken(kind: .punctuator(String(character)), location: location)
  }
}

private extension Character {
  var isGraphQLWhitespace: Bool {
    self == " " || self == "\n" || self == "\r" || self == "\t" || self == ","
  }

  var isGraphQLNameStart: Bool {
    self == "_" || isLetter
  }

  var isGraphQLNameContinue: Bool {
    isGraphQLNameStart || isNumber
  }

  var isLetter: Bool {
    guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
      return false
    }
    return ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
  }
}
