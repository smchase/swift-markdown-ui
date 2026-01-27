import Foundation

extension Sequence where Element == InlineNode {
  /// Extracts math expressions from text nodes, converting `$...$` patterns to `.math` nodes.
  func extractingMath() -> [InlineNode] {
    self.flatMap { inline -> [InlineNode] in
      switch inline {
      case .text(let content):
        return splitTextByMath(content)
      case .emphasis(let children):
        return [.emphasis(children: children.extractingMath())]
      case .strong(let children):
        return [.strong(children: children.extractingMath())]
      case .strikethrough(let children):
        return [.strikethrough(children: children.extractingMath())]
      case .link(let destination, let children):
        return [.link(destination: destination, children: children.extractingMath())]
      default:
        return [inline]
      }
    }
  }
}

/// Splits a text string by `$...$` math delimiters.
/// - Returns: An array of InlineNodes with `.text` and `.math` nodes.
private func splitTextByMath(_ text: String) -> [InlineNode] {
  // Debug: log what text we're processing
  let debugDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".saiman/math-debug")
  try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
  let debugFile = debugDir.appendingPathComponent("extraction.log")
  let logEntry = "splitTextByMath: \(text.prefix(200))\n"
  if let handle = try? FileHandle(forWritingTo: debugFile) {
    handle.seekToEndOfFile()
    handle.write(logEntry.data(using: .utf8)!)
    handle.closeFile()
  } else {
    try? logEntry.write(to: debugFile, atomically: false, encoding: .utf8)
  }

  var result: [InlineNode] = []
  var currentIndex = text.startIndex
  var textBuffer = ""

  while currentIndex < text.endIndex {
    // Look for opening $
    if text[currentIndex] == "$" {
      // Check for $$ (block math delimiter - skip, handled at block level)
      let nextIndex = text.index(after: currentIndex)
      if nextIndex < text.endIndex && text[nextIndex] == "$" {
        textBuffer.append("$")
        currentIndex = nextIndex
        textBuffer.append("$")
        currentIndex = text.index(after: currentIndex)
        continue
      }

      // Look for closing $
      if let (expression, endIndex) = findClosingDelimiter(in: text, from: nextIndex) {
        // Check if this looks like currency (closing $ followed by digit)
        if endIndex < text.endIndex {
          let charAfter = text[endIndex]
          if charAfter.isNumber {
            // This is currency, not math
            textBuffer.append(text[currentIndex])
            currentIndex = nextIndex
            continue
          }
        }

        // Check if opening $ is preceded by digit (likely currency)
        if currentIndex > text.startIndex {
          let charBefore = text[text.index(before: currentIndex)]
          if charBefore.isNumber {
            // This is currency, not math
            textBuffer.append(text[currentIndex])
            currentIndex = nextIndex
            continue
          }
        }

        // Flush text buffer
        if !textBuffer.isEmpty {
          result.append(.text(textBuffer))
          textBuffer = ""
        }

        // Add math node
        let mathLogEntry = "FOUND MATH: \(expression)\n"
        if let handle = try? FileHandle(forWritingTo: debugFile) {
          handle.seekToEndOfFile()
          handle.write(mathLogEntry.data(using: .utf8)!)
          handle.closeFile()
        }
        result.append(.math(expression: expression))
        currentIndex = endIndex
        continue
      }
    }

    textBuffer.append(text[currentIndex])
    currentIndex = text.index(after: currentIndex)
  }

  // Flush remaining text
  if !textBuffer.isEmpty {
    result.append(.text(textBuffer))
  }

  return result.isEmpty ? [.text("")] : result
}

/// Finds the closing `$` delimiter for inline math.
/// - Returns: Tuple of (expression content, index after closing delimiter) or nil if not found.
private func findClosingDelimiter(in text: String, from start: String.Index) -> (String, String.Index)? {
  var index = start
  var expression = ""

  while index < text.endIndex {
    let char = text[index]

    if char == "$" {
      // Found closing delimiter
      // Don't accept empty expressions
      guard !expression.isEmpty else { return nil }
      return (expression, text.index(after: index))
    }

    // Don't allow newlines in inline math
    if char == "\n" {
      return nil
    }

    expression.append(char)
    index = text.index(after: index)
  }

  return nil
}
