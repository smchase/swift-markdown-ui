import Foundation

/// Pre-processes a markdown string to protect LaTeX math expressions from cmark-gfm parsing.
///
/// cmark-gfm strips backslashes before ASCII punctuation (`\{` → `{`, `\$` → `$`, etc.),
/// which corrupts LaTeX expressions. This preprocessor extracts math expressions and replaces
/// them with base64-encoded placeholders that cmark won't mangle. The math extraction step
/// later decodes these placeholders to restore the original expressions.
enum MathPreprocessor {

  // MARK: - Public API

  /// Replaces `$...$` and `$$...$$` math expressions with encoded placeholders.
  ///
  /// Skips math detection inside fenced code blocks and inline code spans.
  static func protect(_ markdown: String) -> String {
    let chars = Array(markdown)
    guard !chars.isEmpty else { return markdown }

    var result: [Character] = []
    var i = 0
    var inFencedCodeBlock = false
    var fenceChar: Character = "`"
    var fenceLength = 0

    while i < chars.count {

      // --- Fenced code block tracking (line-level) ---
      if isLineStart(chars, at: i) {
        let (isFence, fc, fl) = scanFenceOpener(chars, at: i)
        if isFence {
          if inFencedCodeBlock && fc == fenceChar && fl >= fenceLength {
            // Closing fence
            inFencedCodeBlock = false
          } else if !inFencedCodeBlock {
            // Opening fence
            inFencedCodeBlock = true
            fenceChar = fc
            fenceLength = fl
          }
          // Append the full line and continue
          while i < chars.count && chars[i] != "\n" {
            result.append(chars[i])
            i += 1
          }
          if i < chars.count {
            result.append(chars[i]) // the newline
            i += 1
          }
          continue
        }
      }

      // Inside a fenced code block — pass through
      if inFencedCodeBlock {
        result.append(chars[i])
        i += 1
        continue
      }

      // --- Inline code span skipping ---
      if chars[i] == "`" {
        let backtickCount = countRun(chars, at: i, char: "`")
        // Look for matching closing backticks
        var j = i + backtickCount
        var found = false
        while j <= chars.count - backtickCount {
          if chars[j] == "`" && countRun(chars, at: j, char: "`") == backtickCount {
            // Append everything from opening to closing backticks (inclusive)
            let end = j + backtickCount
            for k in i..<end {
              result.append(chars[k])
            }
            i = end
            found = true
            break
          }
          j += 1
        }
        if found { continue }
        // No closing backticks — not a code span, fall through
      }

      // --- Block math: $$ ... $$ ---
      if i + 1 < chars.count && chars[i] == "$" && chars[i + 1] == "$" {
        // The character after $$ must be able to start a math expression.
        // This prevents currency patterns like "$$ prices", "$$$$", "$$," from
        // being mistakenly parsed as block math delimiters.
        if i + 2 < chars.count && canStartBlockMath(chars[i + 2]),
           let (expression, endIndex) = findBlockMathEnd(chars, from: i + 2) {
          let encoded = encode(expression)
          result.append(contentsOf: "$$MATH_BLOCK:\(encoded)$$")
          i = endIndex
          continue
        }
      }

      // --- Inline math: $ ... $ ---
      if chars[i] == "$" {
        // Must not be preceded by a digit (currency like "5$...$")
        let precededByDigit = i > 0 && chars[i - 1].isNumber
        // Must not be preceded by backslash (escaped \$)
        let precededByBackslash = i > 0 && chars[i - 1] == "\\"

        if !precededByDigit && !precededByBackslash {
          if let (expression, endIndex) = findInlineMathEnd(chars, from: i + 1) {
            let encoded = encode(expression)
            result.append(contentsOf: "$MATH:\(encoded)$")
            i = endIndex
            continue
          }
        }
      }

      result.append(chars[i])
      i += 1
    }

    return String(result)
  }

  // MARK: - Placeholder Decoding

  /// Prefix for inline math placeholders.
  static let inlinePrefix = "MATH:"

  /// Prefix for block math placeholders.
  static let blockPrefix = "MATH_BLOCK:"

  /// Decodes a base64-encoded math expression from a placeholder.
  /// Returns the original LaTeX expression, or nil if decoding fails.
  static func decode(_ encoded: String) -> String? {
    guard let data = Data(base64Encoded: encoded) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  // MARK: - Private Helpers

  /// Base64-encodes a string for use in a placeholder.
  private static func encode(_ expression: String) -> String {
    Data(expression.utf8).base64EncodedString()
  }

  /// Finds the closing `$$` for a block math expression.
  /// `from` is the index after the opening `$$`.
  /// Returns (expression content, index after closing `$$`).
  private static func findBlockMathEnd(_ chars: [Character], from start: Int) -> (String, Int)? {
    var j = start
    while j + 1 < chars.count {
      if chars[j] == "$" && chars[j + 1] == "$" {
        let expression = String(chars[start..<j])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return nil }
        return (expression, j + 2)
      }
      j += 1
    }
    return nil
  }

  /// Finds the closing `$` for an inline math expression.
  /// `from` is the index after the opening `$`.
  /// Returns (expression content, index after closing `$`).
  private static func findInlineMathEnd(_ chars: [Character], from start: Int) -> (String, Int)? {
    // Opening $ must not be followed by whitespace, another $, or a digit (currency like $5)
    guard start < chars.count, !chars[start].isWhitespace, chars[start] != "$", !chars[start].isNumber else {
      return nil
    }

    var j = start
    while j < chars.count {
      // Skip escaped dollar signs: \$
      if chars[j] == "\\" && j + 1 < chars.count && chars[j + 1] == "$" {
        j += 2
        continue
      }

      if chars[j] == "$" {
        // Reject if closing $ is followed by a digit (currency: "$5 to $10")
        if j + 1 < chars.count && chars[j + 1].isNumber {
          j += 1
          continue
        }
        // Closing $ must not be preceded by whitespace
        if j > start && chars[j - 1].isWhitespace {
          j += 1
          continue
        }

        let expression = String(chars[start..<j])
        guard !expression.isEmpty else { return nil }
        return (expression, j + 1)
      }

      // No newlines in inline math
      if chars[j] == "\n" {
        return nil
      }

      j += 1
    }
    return nil
  }

  /// Checks if position `i` is at the start of a line.
  private static func isLineStart(_ chars: [Character], at i: Int) -> Bool {
    i == 0 || chars[i - 1] == "\n"
  }

  /// Scans for a fenced code block opener (``` or ~~~) at position `i`.
  /// Returns (isFence, fenceChar, fenceLength).
  private static func scanFenceOpener(_ chars: [Character], at i: Int) -> (Bool, Character, Int) {
    guard i < chars.count else { return (false, "`", 0) }

    // Skip up to 3 leading spaces
    var pos = i
    var spaces = 0
    while pos < chars.count && chars[pos] == " " && spaces < 3 {
      pos += 1
      spaces += 1
    }

    guard pos < chars.count && (chars[pos] == "`" || chars[pos] == "~") else {
      return (false, "`", 0)
    }

    let fc = chars[pos]
    let length = countRun(chars, at: pos, char: fc)

    // Need at least 3
    guard length >= 3 else { return (false, "`", 0) }

    return (true, fc, length)
  }

  /// Whether a character can legitimately start a block math expression.
  /// Letters, digits, backslash (LaTeX commands), opening delimiters, minus (negation),
  /// pipe (absolute value), and newline (multi-line block math) are valid.
  /// Spaces, punctuation, and dollar signs are not — this rejects currency patterns
  /// like "$$ prices", "$$,", and dollar runs like "$$$$".
  private static func canStartBlockMath(_ c: Character) -> Bool {
    c.isLetter || c.isNumber || c == "\\" || c == "{" || c == "(" || c == "[" || c == "-" || c == "|" || c == "=" || c == "+" || c == "\n"
  }

  /// Counts consecutive occurrences of `char` starting at `index`.
  private static func countRun(_ chars: [Character], at index: Int, char: Character) -> Int {
    var count = 0
    var j = index
    while j < chars.count && chars[j] == char {
      count += 1
      j += 1
    }
    return count
  }
}
