import SwiftUI

extension Sequence where Element == InlineNode {
  func renderText(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    mathImages: [String: MathImage],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer
  ) -> Text {
    var renderer = TextInlineRenderer(
      baseURL: baseURL,
      textStyles: textStyles,
      images: images,
      mathImages: mathImages,
      softBreakMode: softBreakMode,
      attributes: attributes
    )
    renderer.render(self)
    return renderer.result
  }
}

private struct TextInlineRenderer {
  var result = Text("")

  private let baseURL: URL?
  private let textStyles: InlineTextStyles
  private let images: [String: Image]
  private let mathImages: [String: MathImage]
  private let softBreakMode: SoftBreak.Mode
  private let attributes: AttributeContainer
  private var shouldSkipNextWhitespace = false

  init(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    mathImages: [String: MathImage],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer
  ) {
    self.baseURL = baseURL
    self.textStyles = textStyles
    self.images = images
    self.mathImages = mathImages
    self.softBreakMode = softBreakMode
    self.attributes = attributes
  }

  mutating func render<S: Sequence>(_ inlines: S) where S.Element == InlineNode {
    for inline in inlines {
      self.render(inline)
    }
  }

  private mutating func render(_ inline: InlineNode) {
    switch inline {
    case .text(let content):
      self.renderText(content)
    case .softBreak:
      self.renderSoftBreak()
    case .html(let content):
      self.renderHTML(content)
    case .image(let source, _):
      self.renderImage(source)
    case .math(let expression):
      self.renderMath(expression)
    case .emphasis(let children), .strong(let children), .strikethrough(let children),
         .link(_, let children):
      // Check if any descendant is a .math node — if so, render children directly
      // so math images are used instead of the attributed string fallback
      if containsMath(children) {
        self.render(children)
      } else {
        self.defaultRender(inline)
      }
    default:
      self.defaultRender(inline)
    }
  }

  /// Returns true if any descendant inline node is a `.math` node.
  private func containsMath(_ inlines: [InlineNode]) -> Bool {
    for inline in inlines {
      switch inline {
      case .math:
        return true
      case .emphasis(let c), .strong(let c), .strikethrough(let c), .link(_, let c):
        if containsMath(c) { return true }
      default:
        break
      }
    }
    return false
  }

  private mutating func renderText(_ text: String) {
    var text = text

    if self.shouldSkipNextWhitespace {
      self.shouldSkipNextWhitespace = false
      text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
    }

    self.defaultRender(.text(text))
  }

  private mutating func renderSoftBreak() {
    switch self.softBreakMode {
    case .space where self.shouldSkipNextWhitespace:
      self.shouldSkipNextWhitespace = false
    case .space:
      self.defaultRender(.softBreak)
    case .lineBreak:
      self.shouldSkipNextWhitespace = true
      self.defaultRender(.lineBreak)
    }
  }

  private mutating func renderHTML(_ html: String) {
    let tag = HTMLTag(html)

    switch tag?.name.lowercased() {
    case "br":
      self.defaultRender(.lineBreak)
      self.shouldSkipNextWhitespace = true
    default:
      self.defaultRender(.html(html))
    }
  }

  private mutating func renderImage(_ source: String) {
    if let image = self.images[source] {
      self.result = self.result + Text(image)
    }
  }

  private mutating func renderMath(_ expression: String) {
    if let mathImage = self.mathImages[expression] {
      // Use template rendering mode so the image inherits foreground color from environment
      self.result = self.result + Text(mathImage.image.renderingMode(.template))
        .foregroundColor(self.attributes.foregroundColor)
        .baselineOffset(mathImage.baselineOffset)
    } else {
      // Show placeholder while loading or on error
      self.result = self.result + Text("$\(expression)$")
    }
  }

  private mutating func defaultRender(_ inline: InlineNode) {
    self.result =
      self.result
      + Text(
        inline.renderAttributedString(
          baseURL: self.baseURL,
          textStyles: self.textStyles,
          softBreakMode: self.softBreakMode,
          attributes: self.attributes
        )
      )
  }
}
