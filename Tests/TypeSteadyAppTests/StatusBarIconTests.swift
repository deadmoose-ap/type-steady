import AppKit
import Testing
@testable import TypeSteadyApp

@Suite("StatusBarIconTests")
@MainActor
struct StatusBarIconTests {
    @Test("uses a square monochrome template image")
    func templateMetadata() {
        let image = StatusBarIcon.makeTemplateImage()

        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
        #expect(image.accessibilityDescription == "TypeSteady")
    }

    @Test("keeps the S channel transparent between two solid panels")
    func splitSilhouetteGeometry() throws {
        let bitmap = try render(StatusBarIcon.makeTemplateImage(), scale: 4)

        #expect(alpha(at: NSPoint(x: 4, y: 9), in: bitmap) > 240)
        #expect(alpha(at: NSPoint(x: 14, y: 9), in: bitmap) > 240)
        #expect(alpha(at: NSPoint(x: 8.2, y: 9), in: bitmap) < 15)
        #expect(alpha(at: NSPoint(x: 11, y: 15), in: bitmap) < 15)
        #expect(alpha(at: NSPoint(x: 8.5, y: 3), in: bitmap) < 15)
        #expect(alpha(at: NSPoint(x: 0.5, y: 0.5), in: bitmap) < 15)
    }

    private func render(_ image: NSImage, scale: Int) throws -> NSBitmapImageRep {
        let width = Int(image.size.width) * scale
        let height = Int(image.size.height) * scale
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw RenderingError.couldNotCreateBitmap
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func alpha(at point: NSPoint, in bitmap: NSBitmapImageRep) -> Int {
        let scale = CGFloat(bitmap.pixelsWide) / StatusBarIcon.pointSize.width
        let pixelX = min(bitmap.pixelsWide - 1, max(0, Int(point.x * scale)))
        let imageY = StatusBarIcon.pointSize.height - point.y
        let pixelY = min(bitmap.pixelsHigh - 1, max(0, Int(imageY * scale)))
        let component = bitmap.colorAt(x: pixelX, y: pixelY)?.alphaComponent ?? 0
        return Int((component * 255).rounded())
    }

    private enum RenderingError: Error {
        case couldNotCreateBitmap
    }
}
