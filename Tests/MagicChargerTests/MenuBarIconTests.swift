import XCTest
import AppKit
@testable import MagicCharger
final class MenuBarIconTests: XCTestCase {
    func testDeviceGlyphsRemainAdaptiveAndContainArtwork() throws {
        for symbol in ["keyboard", "magicmouse"] {
            let image = MenuBarIcon.image(symbol: symbol)
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            XCTAssertTrue((0..<rep.pixelsWide).contains { x in
                (0..<rep.pixelsHigh).contains { y in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
            })
        }
    }
}
