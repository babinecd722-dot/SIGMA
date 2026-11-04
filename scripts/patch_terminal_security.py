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
    path.chmod(path.stat().st_mode | stat.S_IWUSR)
    path.write_text(source)
