import SwiftUI
import MathJaxSwift
import SwiftDraw

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Represents a rendered math image with layout information.
public struct MathImage: Sendable {
  /// The rendered image.
  public let image: Image

  /// The baseline offset for proper text alignment.
  public let baselineOffset: CGFloat

  /// The size of the rendered image.
  public let size: CGSize
}

/// Singleton renderer for LaTeX math expressions.
@MainActor
public final class MathRenderer {
  /// Shared instance.
  public static let shared = MathRenderer()

  /// Cache of rendered math images keyed by expression + parameters.
  private var cache: [CacheKey: MathImage] = [:]

  /// MathJax instance for rendering.
  private var mathJax: MathJax?

  /// Whether MathJax has been initialized.
  private var isInitialized = false

  private struct CacheKey: Hashable {
    let expression: String
    let isBlock: Bool
    let fontSize: CGFloat
    let displayScale: CGFloat
  }

  private init() {}

  /// Initializes MathJax if needed.
  private func initializeMathJax() throws {
    guard !isInitialized else { return }

    mathJax = try MathJax(preferredOutputFormat: .svg)
    isInitialized = true
  }

  /// Renders a LaTeX math expression to an image.
  /// - Parameters:
  ///   - expression: The LaTeX math expression (without delimiters).
  ///   - isBlock: Whether this is display/block math (centered, larger).
  ///   - fontSize: The surrounding text font size for scaling.
  ///   - displayScale: The display scale factor.
  ///   - foregroundColor: The color for the math rendering.
  /// - Returns: A `MathImage` with the rendered result, or nil on failure.
  public func render(
    expression: String,
    isBlock: Bool = false,
    fontSize: CGFloat = 16,
    displayScale: CGFloat = 2.0,
    foregroundColor: Color = .primary
  ) async -> MathImage? {
    let cacheKey = CacheKey(
      expression: expression,
      isBlock: isBlock,
      fontSize: fontSize,
      displayScale: displayScale
    )

    // Check cache
    if let cached = cache[cacheKey] {
      return cached
    }

    do {
      try initializeMathJax()

      guard let mathJax = mathJax else { return nil }

      // Render to SVG
      let svgString = try await mathJax.tex2svg(expression)

      // Debug: write raw SVG to file
      let debugDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".saiman/math-debug")
      try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
      let sanitizedExpr = expression.prefix(20).replacingOccurrences(of: "/", with: "_")
      let debugFile = debugDir.appendingPathComponent("\(sanitizedExpr).svg")
      try? svgString.write(to: debugFile, atomically: true, encoding: .utf8)

      // Also write geometry info
      let infoFile = debugDir.appendingPathComponent("\(sanitizedExpr).txt")
      var info = "Expression: \(expression)\n"
      info += "SVG length: \(svgString.count)\n"
      info += "SVG preview: \(svgString.prefix(800))\n"

      // Parse SVG
      guard let svg = SVG(xml: svgString) else {
        print("MathRenderer: Failed to parse SVG")
        return nil
      }

      // Extract geometry from SVG attributes (in ex units)
      guard let geometry = SVGGeometry(svgString: svgString) else {
        print("MathRenderer: Failed to extract geometry")
        return nil
      }

      info += "Geometry: width=\(geometry.widthEx)ex, height=\(geometry.heightEx)ex, vAlign=\(geometry.verticalAlignEx)ex\n"

      // Convert ex units to points: 1ex ≈ 0.5em ≈ fontSize * 0.5
      // Then scale for display
      let exToPoints = fontSize * 0.5
      let width = geometry.widthEx * exToPoints * displayScale
      let height = geometry.heightEx * exToPoints * displayScale

      info += "Calculated: width=\(width), height=\(height), fontSize=\(fontSize), displayScale=\(displayScale)\n"
      info += "Final: width=\(max(width, 4)), height=\(max(height, 4))\n"
      try? info.write(to: infoFile, atomically: true, encoding: .utf8)

      // Ensure minimum size
      let finalWidth = max(width, 4)
      let finalHeight = max(height, 4)

      // Rasterize the SVG
      let scaledSVG = svg.sized(CGSize(width: finalWidth, height: finalHeight))

      #if os(macOS)
      let nsImage = scaledSVG.rasterize(with: CGSize(width: finalWidth, height: finalHeight), scale: 1.0)
      // Create a properly sized image for display (divide by displayScale)
      nsImage.size = CGSize(width: finalWidth / displayScale, height: finalHeight / displayScale)
      let image = Image(nsImage: nsImage)
      #else
      let uiImage = scaledSVG.rasterize(size: CGSize(width: finalWidth, height: finalHeight), scale: displayScale)
      let image = Image(uiImage: uiImage)
      #endif

      // Calculate baseline offset (convert from ex to points)
      let baselineOffset = geometry.verticalAlignEx * exToPoints

      let mathImage = MathImage(
        image: image,
        baselineOffset: baselineOffset,
        size: CGSize(width: finalWidth / displayScale, height: finalHeight / displayScale)
      )

      // Cache result
      cache[cacheKey] = mathImage

      return mathImage
    } catch {
      print("MathRenderer error: \(error)")
      return nil
    }
  }

  /// Clears the render cache.
  public func clearCache() {
    cache.removeAll()
  }
}

/// Extracts geometry information from MathJax SVG output.
/// MathJax outputs dimensions in "ex" units.
struct SVGGeometry {
  let widthEx: CGFloat
  let heightEx: CGFloat
  let verticalAlignEx: CGFloat

  init?(svgString: String) {
    // Extract width and height from SVG attributes (in ex units)
    // MathJax SVGs have attributes like width="5.2ex" height="2.1ex"
    guard let w = Self.extractDimension(from: svgString, attribute: "width"),
          let h = Self.extractDimension(from: svgString, attribute: "height") else {
      return nil
    }

    self.widthEx = w
    self.heightEx = h

    // Extract vertical-align from style attribute (also in ex)
    // MathJax SVGs typically have style="vertical-align: -0.566ex;"
    self.verticalAlignEx = Self.extractVerticalAlign(from: svgString) ?? 0
  }

  private static func extractDimension(from svg: String, attribute: String) -> CGFloat? {
    // Look for attribute="Xex" pattern
    let pattern = "\(attribute)=\"([\\d.]+)ex\""
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
          let range = Range(match.range(at: 1), in: svg),
          let value = Double(svg[range]) else {
      return nil
    }
    return CGFloat(value)
  }

  private static func extractVerticalAlign(from svg: String) -> CGFloat? {
    // Look for vertical-align: Xex pattern in style
    let pattern = "vertical-align:\\s*(-?[\\d.]+)ex"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
          let range = Range(match.range(at: 1), in: svg),
          let value = Double(svg[range]) else {
      return nil
    }
    return CGFloat(value)
  }
}
