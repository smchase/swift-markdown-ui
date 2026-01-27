import Foundation

extension Sequence where Element == BlockNode {
  /// Extracts math blocks from paragraphs containing only `$$...$$` content.
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
      // Check if paragraph contains only a block math expression
      if let mathBlock = extractMathBlock(from: content) {
        return [mathBlock]
      }
      // Otherwise, extract inline math from the paragraph content
      return [.paragraph(content: content.extractingMath())]

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

/// Checks if a paragraph contains only a `$$...$$` block math expression.
/// - Returns: A `.mathBlock` node if the paragraph is purely block math, otherwise nil.
private func extractMathBlock(from content: [InlineNode]) -> BlockNode? {
  // Collect all text content, ignoring soft breaks
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
      // If there's any non-text content, this isn't a pure math block
      return nil
    }
  }

  let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)

  // Check for $$...$$ pattern
  guard trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") && trimmed.count > 4 else {
    return nil
  }

  // Extract the expression (remove $$ from both ends)
  let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 2)
  let endIndex = trimmed.index(trimmed.endIndex, offsetBy: -2)

  guard startIndex < endIndex else { return nil }

  let expression = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)

  guard !expression.isEmpty else { return nil }

  return .mathBlock(expression: expression)
}
