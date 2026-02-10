import Foundation

extension Sequence where Element == BlockNode {
  /// Extracts math blocks from paragraphs containing `$$...$$` content.
  /// Also extracts inline math from all inline content.
  func extractingMath() -> [BlockNode] {
    self.flatMap { block -> [BlockNode] in
      block.extractingMath()
    }
  }
}

extension BlockNode {
  /// Extracts math from this block node.
  func extractingMath() -> [BlockNode] {
    switch self {
    case .paragraph(let content):
      return extractBlockMathFromParagraph(content: content)

    case .heading(let level, let content):
      return [.heading(level: level, content: content.extractingMath())]

    case .blockquote(let children):
      return [.blockquote(children: children.extractingMath())]

    case .bulletedList(let isTight, let items):
      return [.bulletedList(
        isTight: isTight,
        items: items.map { RawListItem(children: $0.children.extractingMath()) }
      )]

    case .numberedList(let isTight, let start, let items):
      return [.numberedList(
        isTight: isTight,
        start: start,
        items: items.map { RawListItem(children: $0.children.extractingMath()) }
      )]

    case .taskList(let isTight, let items):
      return [.taskList(
        isTight: isTight,
        items: items.map {
          RawTaskListItem(isCompleted: $0.isCompleted, children: $0.children.extractingMath())
        }
      )]

    case .table(let columnAlignments, let rows):
      return [.table(
        columnAlignments: columnAlignments,
        rows: rows.map { row in
          RawTableRow(cells: row.cells.map { cell in
            RawTableCell(content: cell.content.extractingMath())
          })
        }
      )]

    default:
      return [self]
    }
  }
}

/// Extracts block math placeholders from a paragraph, splitting into multiple blocks.
private func extractBlockMathFromParagraph(content: [InlineNode]) -> [BlockNode] {
  // Collect all text to find $$MATH_BLOCK:....$$ placeholders
  var fullText = ""
  for inline in content {
    switch inline {
    case .text(let text):
      fullText += text
    case .softBreak:
      fullText += " "
    case .lineBreak:
      fullText += "\n"
    default:
      // Non-text content — just extract inline math and return as paragraph
      return [.paragraph(content: content.extractingMath())]
    }
  }

  // Look for $$MATH_BLOCK:base64$$ placeholder
  let prefix = "$$" + MathPreprocessor.blockPrefix
  let suffix = "$$"

  guard let prefixRange = fullText.range(of: prefix) else {
    // No block math placeholder — extract inline math only
    return [.paragraph(content: content.extractingMath())]
  }

  let searchStart = prefixRange.upperBound
  guard let suffixRange = fullText.range(of: suffix, range: searchStart..<fullText.endIndex) else {
    return [.paragraph(content: content.extractingMath())]
  }

  // Decode the base64 expression
  let encoded = String(fullText[searchStart..<suffixRange.lowerBound])
  guard let expression = MathPreprocessor.decode(encoded), !expression.isEmpty else {
    return [.paragraph(content: content.extractingMath())]
  }

  var result: [BlockNode] = []

  // Text before the placeholder
  let beforeText = String(fullText[..<prefixRange.lowerBound])
    .trimmingCharacters(in: .whitespacesAndNewlines)
  if !beforeText.isEmpty {
    result.append(.paragraph(content: [InlineNode.text(beforeText)].extractingMath()))
  }

  // The math block
  result.append(.mathBlock(expression: expression))

  // Text after the placeholder — recursively process for more block math
  let afterText = String(fullText[suffixRange.upperBound...])
    .trimmingCharacters(in: .whitespacesAndNewlines)
  if !afterText.isEmpty {
    let afterBlocks = extractBlockMathFromParagraph(content: [.text(afterText)])
    result.append(contentsOf: afterBlocks)
  }

  return result.isEmpty ? [.paragraph(content: content.extractingMath())] : result
}
