import AppKit

// Keep the device glyph adaptive; status emoji are rendered separately as text.
enum MenuBarIcon {
    static func image(symbol: String) -> NSImage {
        let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.black]))
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            if let glyph = glyph {
                let scale = min(18 / glyph.size.width, 14 / glyph.size.height)
                let size = NSSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
                glyph.draw(in: NSRect(x: (18 - size.width) / 2, y: (18 - size.height) / 2, width: size.width, height: size.height))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
