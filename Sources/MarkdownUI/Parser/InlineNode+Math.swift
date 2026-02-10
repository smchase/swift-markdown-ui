import Foundation

extension Sequence where Element == InlineNode {
  /// Extracts math expressions from text nodes, converting `$MATH:base64$` placeholders to `.math` nodes.
  func extractingMath() -> [InlineNode] {
    self.flatMap { inline -> [InlineNode] in
      switch inline {
      case .text(let content):
        return splitTextByMathPlaceholders(content)
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

/// Splits a text string by `$MATH:base64$` placeholders.
/// Returns an array of InlineNodes with `.text` and `.math` nodes.
private func splitTextByMathPlaceholders(_ text: String) -> [InlineNode] {
  let prefix = "$" + MathPreprocessor.inlinePrefix
  var result: [InlineNode] = []
  var remaining = text[text.startIndex..<text.endIndex]

  while !remaining.isEmpty {
    // Look for the next $MATH: placeholder
    guard let prefixRange = remaining.range(of: prefix) else {
      // No more placeholders — append remaining text
      let s = String(remaining)
      if !s.isEmpty { result.append(.text(s)) }
      break
    }

    // Make sure this isn't part of $$MATH_BLOCK: (check for preceding $)
    if prefixRange.lowerBound > remaining.startIndex {
      let charBefore = remaining[remaining.index(before: prefixRange.lowerBound)]
      if charBefore == "$" {
        // This is $$MATH_BLOCK:, not $MATH: — skip past this $
        let beforeAndDollar = String(remaining[remaining.startIndex...prefixRange.lowerBound])
        result.append(.text(beforeAndDollar))
        remaining = remaining[remaining.index(after: prefixRange.lowerBound)..<remaining.endIndex]
        continue
      }
    }

    // Text before the placeholder
    let before = String(remaining[remaining.startIndex..<prefixRange.lowerBound])
    if !before.isEmpty {
      result.append(.text(before))
    }

    // Find closing $
    let searchStart = prefixRange.upperBound
    guard let closingRange = remaining.range(of: "$", range: searchStart..<remaining.endIndex) else {
      // No closing $ — treat as regular text
      let s = String(remaining[prefixRange.lowerBound..<remaining.endIndex])
      if !s.isEmpty { result.append(.text(s)) }
      break
    }

    // Decode the base64 expression
    let encoded = String(remaining[searchStart..<closingRange.lowerBound])
    if let expression = MathPreprocessor.decode(encoded), !expression.isEmpty {
      result.append(.math(expression: expression))
    } else {
      // Decoding failed — output as text
      let s = String(remaining[prefixRange.lowerBound..<closingRange.upperBound])
      result.append(.text(s))
    }

    remaining = remaining[closingRange.upperBound..<remaining.endIndex]
  }

  return result.isEmpty ? [.text("")] : result
}
