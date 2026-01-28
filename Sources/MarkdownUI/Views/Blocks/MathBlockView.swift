import SwiftUI

struct MathBlockView: View {
  @Environment(\.theme.mathBlock) private var mathBlock
  @Environment(\.displayScale) private var displayScale
  @Environment(\.textStyle) private var textStyle

  @State private var mathImage: MathImage?

  private let expression: String

  /// The current font size from the text style environment.
  private var fontSize: CGFloat {
    var attributes = AttributeContainer()
    textStyle._collectAttributes(in: &attributes)
    return attributes.fontProperties?.scaledSize ?? FontProperties.defaultSize
  }

  init(expression: String) {
    self.expression = expression
  }

  var body: some View {
    self.mathBlock.makeBody(
      configuration: .init(
        label: .init(self.label),
        content: .init(block: .mathBlock(expression: self.expression))
      )
    )
  }

  @ViewBuilder
  private var label: some View {
    TextStyleAttributesReader { attributes in
      if let mathImage = self.mathImage {
        mathImage.image
          .renderingMode(.template)
          .foregroundColor(attributes.foregroundColor)
      } else {
        // Show placeholder while loading or if rendering failed
        Text("$$\(expression)$$")
      }
    }
    .task(id: expression) {
      await renderMath()
    }
  }

  private func renderMath() async {
    // Capture font size before async rendering
    let fontSize = self.fontSize

    mathImage = await MathRenderer.shared.render(
      expression: expression,
      isBlock: true,
      fontSize: fontSize,
      displayScale: displayScale
    )
  }
}
