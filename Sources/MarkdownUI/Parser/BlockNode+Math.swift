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
///
/// When `$$...$$` appears on the same line(s) as rich inline content (e.g. `**Total:**\n$$...$$`),
/// cmark merges them into a single paragraph with mixed inline nodes (strong, softBreak, text, etc.).
/// We scan individual text nodes for the placeholder rather than requiring an all-text paragraph.
private func extractBlockMathFromParagraph(content: [InlineNode]) -> [BlockNode] {
  let prefix = "$$" + MathPreprocessor.blockPrefix
  let suffix = "$$"

  // Find the first text node containing a block math placeholder
  for (index, inline) in content.enumerated() {
    guard case .text(let text) = inline,
          let prefixRange = text.range(of: prefix) else {
      continue
    }

    let searchStart = prefixRange.upperBound
    guard let suffixRange = text.range(of: suffix, range: searchStart..<text.endIndex) else {
      continue
    }

    // Decode the base64 expression
    let encoded = String(text[searchStart..<suffixRange.lowerBound])
    guard let expression = MathPreprocessor.decode(encoded), !expression.isEmpty else {
      continue
    }

    var result: [BlockNode] = []

    // Everything before the placeholder: preceding inline nodes + text before the marker
    var beforeInlines = Array(content[..<index])
    let beforeText = String(text[..<prefixRange.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !beforeText.isEmpty {
      beforeInlines.append(.text(beforeText))
    }
    // Strip trailing soft/line breaks between preceding content and the math block
    while let last = beforeInlines.last {
      if case .softBreak = last { beforeInlines.removeLast() }
      else if case .lineBreak = last { beforeInlines.removeLast() }
      else { break }
    }
    if !beforeInlines.isEmpty {
      result.append(.paragraph(content: beforeInlines.extractingMath()))
    }

    // The math block
    result.append(.mathBlock(expression: expression))

    // Everything after the placeholder: remaining text + subsequent inline nodes
    var afterInlines: [InlineNode] = []
    let afterText = String(text[suffixRange.upperBound...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !afterText.isEmpty {
      afterInlines.append(.text(afterText))
    }
    if index + 1 < content.count {
      afterInlines.append(contentsOf: content[(index + 1)...])
    }
    // Strip leading soft/line breaks after the math block
    while let first = afterInlines.first {
      if case .softBreak = first { afterInlines.removeFirst() }
      else if case .lineBreak = first { afterInlines.removeFirst() }
      else { break }
    }
    if !afterInlines.isEmpty {
      result.append(contentsOf: extractBlockMathFromParagraph(content: afterInlines))
    }

    return result.isEmpty ? [.paragraph(content: content.extractingMath())] : result
  }

  // No block math placeholder found — extract inline math only
  return [.paragraph(content: content.extractingMath())]
}
