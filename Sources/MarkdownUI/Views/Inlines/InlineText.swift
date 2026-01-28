import SwiftUI

struct InlineText: View {
  @Environment(\.inlineImageProvider) private var inlineImageProvider
  @Environment(\.baseURL) private var baseURL
  @Environment(\.imageBaseURL) private var imageBaseURL
  @Environment(\.softBreakMode) private var softBreakMode
  @Environment(\.theme) private var theme
  @Environment(\.displayScale) private var displayScale

  @State private var inlineImages: [String: Image] = [:]
  @State private var mathImages: [String: MathImage] = [:]

  private let inlines: [InlineNode]

  /// Inlines with math expressions extracted from text nodes.
  private var processedInlines: [InlineNode] {
    inlines.extractingMath()
  }

  init(_ inlines: [InlineNode]) {
    self.inlines = inlines
  }

  var body: some View {
    TextStyleAttributesReader { attributes in
      self.processedInlines.renderText(
        baseURL: self.baseURL,
        textStyles: .init(
          code: self.theme.code,
          emphasis: self.theme.emphasis,
          strong: self.theme.strong,
          strikethrough: self.theme.strikethrough,
          link: self.theme.link
        ),
        images: self.inlineImages,
        mathImages: self.mathImages,
        softBreakMode: self.softBreakMode,
        attributes: attributes
      )
    }
    .task(id: self.inlines) {
      async let images = self.loadInlineImages()
      async let math = self.loadMathImages()
      self.inlineImages = (try? await images) ?? [:]
      self.mathImages = await math
    }
  }

  private func loadInlineImages() async throws -> [String: Image] {
    let images = Set(self.inlines.compactMap(\.imageData))
    guard !images.isEmpty else { return [:] }

    return try await withThrowingTaskGroup(of: (String, Image).self) { taskGroup in
      for image in images {
        guard let url = URL(string: image.source, relativeTo: self.imageBaseURL) else {
          continue
        }

        taskGroup.addTask {
          (image.source, try await self.inlineImageProvider.image(with: url, label: image.alt))
        }
      }

      var inlineImages: [String: Image] = [:]

      for try await result in taskGroup {
        inlineImages[result.0] = result.1
      }

      return inlineImages
    }
  }

  private func loadMathImages() async -> [String: MathImage] {
    let mathExpressions = collectMathExpressions(from: processedInlines)
    guard !mathExpressions.isEmpty else { return [:] }

    return await withTaskGroup(of: (String, MathImage?).self) { taskGroup in
      for expression in mathExpressions {
        taskGroup.addTask {
          let image = await MathRenderer.shared.render(
            expression: expression,
            isBlock: false,
            fontSize: 16,  // Will be adjusted by the renderer
            displayScale: self.displayScale
          )
          return (expression, image)
        }
      }

      var mathImages: [String: MathImage] = [:]

      for await result in taskGroup {
        if let image = result.1 {
          mathImages[result.0] = image
        }
      }

      return mathImages
    }
  }

  private func collectMathExpressions(from inlines: [InlineNode]) -> Set<String> {
    var expressions = Set<String>()

    for inline in inlines {
      switch inline {
      case .math(let expression):
        expressions.insert(expression)
      case .emphasis(let children), .strong(let children), .strikethrough(let children):
        expressions.formUnion(collectMathExpressions(from: children))
      case .link(_, let children):
        expressions.formUnion(collectMathExpressions(from: children))
      default:
        break
      }
    }

    return expressions
  }
}
