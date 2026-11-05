"""Bounds for untrusted terminal graphics in the pinned SwiftTerm checkout."""
from pathlib import Path
import stat


def patch_terminal_security(checkouts: Path):
    path = checkouts / "SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift"
    source = path.read_text()
    old = """        guard let img = TTImage(data: data) else {
            return
        }
        insertImage(img, terminal: source,"""
    new = """        // Encoded byte size does not bound the decoded raster: a tiny
        // compressed PNG can advertise gigapixels. Check metadata before
        // UIKit/AppKit gets a chance to allocate or decode that raster.
        guard terminalInlineImageWithinLimits(data),
              let img = TTImage(data: data) else {
            return
        }
        insertImage(img, terminal: source,"""
    helper = """// Match the existing Sixel 64 MiB RGBA ceiling for inline iTerm images.
// Metadata inspection explicitly disables eager raster caching.
func terminalInlineImageWithinLimits(_ data: Data) -> Bool {
    guard data.count <= 8 * 1024 * 1024,
          let source = CGImageSourceCreateWithData(data as CFData,
              [kCGImageSourceShouldCache: false] as CFDictionary),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
          let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
          width.isFinite, height.isFinite, width > 0, height > 0 else { return false }
    return width <= Double(16 * 1024 * 1024) / height
}

"""
    if new not in source:
        if source.count(old) != 1:
            raise RuntimeError(f"Unexpected terminal inline image decoder: {path}")
        source = source.replace(old, new, 1)
    if helper not in source:
        anchor = 'let SwiftTermUnderlineStyleKey = NSAttributedString.Key("SwiftTermUnderlineStyle")'
        if source.count(anchor) != 1:
            raise RuntimeError(f"Unexpected terminal graphics source: {path}")
        source = source.replace(anchor, helper + anchor, 1)

    render_helper = """// Bound the physical backing of every stripe, including outward pixel
// rounding and the final partially occupied terminal row. The same scale
// is passed to the iOS renderer; a default screen scale could exceed it.
func terminalRenderedImageWithinLimits(_ size: CGSize, cellSize: CGSize, scale: CGFloat) -> Bool {
    guard size.width.isFinite, size.height.isFinite,
          size.width > 0, size.height > 0,
          cellSize.width.isFinite, cellSize.height.isFinite,
          cellSize.width > 0, cellSize.height > 0,
          scale.isFinite, scale >= 1,
          size.width >= 1 / scale, size.height >= 1 / scale else { return false }
    let width = ceil(size.width * scale)
    let height = ceil(size.height * scale)
    let stripeHeight = ceil(cellSize.height * scale)
    let rows = ceil(size.height / cellSize.height)
    guard width.isFinite, height.isFinite, stripeHeight.isFinite, rows.isFinite,
          width > 0, width <= 8192, height > 0, height <= 8192,
          stripeHeight > 0, stripeHeight <= 8192, rows > 0, rows <= 8192 else { return false }
    let rasterHeight = rows * stripeHeight
    return rasterHeight <= 8192 && width <= CGFloat(16 * 1024 * 1024) / rasterHeight
}

"""
    if render_helper not in source:
        anchor = 'let SwiftTermUnderlineStyleKey = NSAttributedString.Key("SwiftTermUnderlineStyle")'
        if source.count(anchor) != 1:
            raise RuntimeError(f"Unexpected terminal render source: {path}")
        source = source.replace(anchor, render_helper + anchor, 1)

    before_metrics = """        let displayScale = metrics.imageScale
\x20\x20\x20\x20\x20\x20\x20\x20
        // Converts a size request"""
    after_metrics = """        let displayScale = metrics.imageScale
        guard cellSize.width.isFinite, cellSize.height.isFinite,
              cellSize.width > 0, cellSize.height > 0,
              displayScale.isFinite, displayScale >= 1,
              img.size.width.isFinite, img.size.height.isFinite,
              img.size.width > 0, img.size.height > 0 else { return }
\x20\x20\x20\x20\x20\x20\x20\x20
        // Converts a size request"""
    if after_metrics not in source:
        if source.count(before_metrics) != 1:
            raise RuntimeError(f"Unexpected terminal image metrics: {path}")
        source = source.replace(before_metrics, after_metrics, 1)
    before_aspect = """        if preserveAspectRatio {
            switch (widthRequest, heightRequest) {"""
    after_aspect = """        // Validate before scale() allocates a bitmap, then again after
        // preserving aspect ratio can expand an otherwise tiny dimension.
        guard terminalRenderedImageWithinLimits(CGSize(width: width, height: height),
                  cellSize: cellSize, scale: displayScale) else { return }
        var shouldScaleImage = false
        if preserveAspectRatio {
            switch (widthRequest, heightRequest) {"""
    if after_aspect not in source:
        if source.count(before_aspect) != 1:
            raise RuntimeError(f"Unexpected terminal image aspect handling: {path}")
        source = source.replace(before_aspect, after_aspect, 1)
    before_scale = """                img = scale (image: img, size: CGSize (width: width, height: height))
            }
        }
\x20\x20\x20\x20\x20\x20\x20\x20
        let rows = Int (ceil (height/cellSize.height))"""
    after_scale = """                shouldScaleImage = true
            }
        }
        guard terminalRenderedImageWithinLimits(CGSize(width: width, height: height),
                  cellSize: cellSize, scale: displayScale) else { return }
        if shouldScaleImage {
            // scale() uses a 1x context. Refuse subpixel intermediates
            // instead of asking UIKit to create a zero-pixel bitmap.
            guard width >= 1, height >= 1 else { return }
            img = scale (image: img, size: CGSize (width: width, height: height))
        }
        // The guard bounds this quotient before conversion to Int.
        let rows = Int (ceil (height/cellSize.height))"""
    if after_scale not in source:
        if source.count(before_scale) != 1:
            raise RuntimeError(f"Unexpected terminal image scale: {path}")
        source = source.replace(before_scale, after_scale, 1)
    before_stripe = "dstHeight: cellSize.height, size: stripeSize) else {"
    after_stripe = "dstHeight: cellSize.height, size: stripeSize, scale: displayScale) else {"
    if after_stripe not in source:
        if source.count(before_stripe) != 1:
            raise RuntimeError(f"Unexpected terminal stripe renderer: {path}")
        source = source.replace(before_stripe, after_stripe, 1)
    path.chmod(path.stat().st_mode | stat.S_IWUSR)
    path.write_text(source)

    for platform in ["iOS/iOSTerminalView.swift", "Mac/MacTerminalView.swift"]:
        platform_path = checkouts / "SwiftTerm/Sources/SwiftTerm" / platform
        platform_source = platform_path.read_text()
        before = "srcHeight: CGFloat, dstHeight: CGFloat, size: CGSize) -> TTImage? {"
        after = "srcHeight: CGFloat, dstHeight: CGFloat, size: CGSize, scale: CGFloat) -> TTImage? {"
        if after not in platform_source:
            if platform_source.count(before) != 1:
                raise RuntimeError(f"Unexpected terminal stripe signature: {platform_path}")
            platform_source = platform_source.replace(before, after, 1)
        if platform.startswith("iOS"):
            before = "UIGraphicsBeginImageContextWithOptions(size, false, 0.0)"
            after = "UIGraphicsBeginImageContextWithOptions(size, false, scale)"
            if after not in platform_source:
                if platform_source.count(before) != 1:
                    raise RuntimeError(f"Unexpected iOS terminal stripe scale: {platform_path}")
                platform_source = platform_source.replace(before, after, 1)
            before = """        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else {"""
            after = """        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else {"""
            if after not in platform_source:
                if platform_source.count(before) != 1:
                    raise RuntimeError(f"Unexpected iOS terminal stripe context: {platform_path}")
                platform_source = platform_source.replace(before, after, 1)
            before = """        let stripe = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return stripe"""
            after = """        let stripe = UIGraphicsGetImageFromCurrentImageContext()
        return stripe"""
            if after not in platform_source:
                if platform_source.count(before) != 1:
                    raise RuntimeError(f"Unexpected iOS terminal stripe cleanup: {platform_path}")
                platform_source = platform_source.replace(before, after, 1)
        platform_path.chmod(platform_path.stat().st_mode | stat.S_IWUSR)
        platform_path.write_text(platform_source)

    terminal_path = checkouts / "SwiftTerm/Sources/SwiftTerm/Terminal.swift"
    terminal_source = terminal_path.read_text()
    start = terminal_source.index("        func parseDimension(_ kv: [String:String], key: String) -> ImageSizeRequest {")
    end = terminal_source.index("\n        guard let equalIdx", start)
    dimension_parser = terminal_source[start:end]
    # Missing or explicit auto stays automatic. Malformed/oversized
    # explicit requests are invalid, not a request to fall back to auto.
    dimension_parser = dimension_parser.replace("                return .auto\n            }\n            if v.hasSuffix", "                return .pixels(0)\n            }\n            if v.hasSuffix")
    dimension_parser = dimension_parser.replace("                return .auto\n            }\n            if let n = Int (v)", "                return .pixels(0)\n            }\n            if let n = Int (v)")
    dimension_parser = dimension_parser.replace("            return .auto\n        }", "            return .pixels(0)\n        }")
    if "return .pixels(0)" not in dimension_parser:
        raise RuntimeError(f"Unexpected terminal dimension parser: {terminal_path}")
    terminal_source = terminal_source[:start] + dimension_parser + terminal_source[end:]
    terminal_path.chmod(terminal_path.stat().st_mode | stat.S_IWUSR)
    terminal_path.write_text(terminal_source)
