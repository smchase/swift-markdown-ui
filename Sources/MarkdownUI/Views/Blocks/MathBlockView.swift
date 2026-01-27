import SwiftUI

struct MathBlockView: View {
  @Environment(\.theme.mathBlock) private var mathBlock
  @Environment(\.displayScale) private var displayScale

  @State private var mathImage: MathImage?
  @State private var isLoading = true

  private let expression: String

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
      let fontSize = attributes.fontProperties?.size ?? 16

      if let mathImage = self.mathImage {
        mathImage.image
          .renderingMode(.template)
          .foregroundColor(attributes.foregroundColor)
      } else if isLoading {
        // Show placeholder while loading
        Text("$$\(expression)$$")
          .font(.system(size: fontSize, design: .monospaced))
          .foregroundColor(.secondary)
      } else {
        // Show original if rendering failed
        Text("$$\(expression)$$")
          .font(.system(size: fontSize, design: .monospaced))
      }
    }
    .task(id: expression) {
      await renderMath()
    }
  }

  private func renderMath() async {
    isLoading = true

    // Get font size from environment
    let fontSize: CGFloat = 16  // Default, will be overridden by TextStyleAttributesReader

    mathImage = await MathRenderer.shared.render(
      expression: expression,
      isBlock: true,
      fontSize: fontSize,
      displayScale: displayScale
    )

    isLoading = false
  }
}
