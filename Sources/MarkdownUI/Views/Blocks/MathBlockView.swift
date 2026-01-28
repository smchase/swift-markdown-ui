import SwiftUI

struct MathBlockView: View {
  @Environment(\.theme.mathBlock) private var mathBlock
  @Environment(\.displayScale) private var displayScale

  @State private var mathImage: MathImage?

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
    mathImage = await MathRenderer.shared.render(
      expression: expression,
      isBlock: true,
      fontSize: 16,
      displayScale: displayScale
    )
  }
}
