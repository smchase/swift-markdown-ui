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
      // Check for $$...$$ block math and split if needed
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

/// Extracts block math ($$...$$) from a paragraph, potentially splitting it into multiple blocks.
/// Returns: Array of blocks - could be single paragraph, or paragraph + mathBlock + paragraph etc.
private func extractBlockMathFromParagraph(content: [InlineNode]) -> [BlockNode] {
  // First, collect all text to find $$...$$ patterns
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
      // Non-text content - just extract inline math and return as single paragraph
      return [.paragraph(content: content.extractingMath())]
    }
  }

  // Look for $$...$$ pattern
  guard let mathRange = findBlockMath(in: fullText) else {
    // No block math, just extract inline math
    return [.paragraph(content: content.extractingMath())]
  }

  var result: [BlockNode] = []

  // Text before the math block
  let beforeText = String(fullText[..<mathRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
  if !beforeText.isEmpty {
    result.append(.paragraph(content: [InlineNode.text(beforeText)].extractingMath()))
  }

  // The math block itself
  let mathStart = fullText.index(mathRange.lowerBound, offsetBy: 2)
  let mathEnd = fullText.index(mathRange.upperBound, offsetBy: -2)
  if mathStart < mathEnd {
    let expression = String(fullText[mathStart..<mathEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    if !expression.isEmpty {
      result.append(.mathBlock(expression: expression))
    }
  }

  // Text after the math block - recursively process for more $$...$$
  let afterText = String(fullText[mathRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
  if !afterText.isEmpty {
    let afterBlocks = extractBlockMathFromParagraph(content: [.text(afterText)])
    result.append(contentsOf: afterBlocks)
  }

  return result.isEmpty ? [.paragraph(content: content.extractingMath())] : result
}

/// Finds the first $$...$$ pattern in the text.
/// Returns the range including the $$ delimiters.
private func findBlockMath(in text: String) -> Range<String.Index>? {
  guard let startRange = text.range(of: "$$") else { return nil }

  let searchStart = text.index(startRange.upperBound, offsetBy: 0)
  guard searchStart < text.endIndex,
        let endRange = text.range(of: "$$", range: searchStart..<text.endIndex) else {
    return nil
  }

  return startRange.lowerBound..<endRange.upperBound
}
