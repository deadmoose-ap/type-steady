import AppKit

@MainActor
enum StatusBarIcon {
    static let pointSize = NSSize(width: 18, height: 18)

    static func makeTemplateImage() -> NSImage {
        let image = NSImage(size: pointSize, flipped: false) { drawingRect in
            NSColor.black.setFill()
            leftPanel(in: drawingRect).fill()
            rightPanel(in: drawingRect).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TypeSteady"
        return image
    }

    private static func leftPanel(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(194, 148, in: rect))
        path.line(to: point(565, 148, in: rect))
        path.curve(
            to: point(476, 343, in: rect),
            controlPoint1: point(565, 254, in: rect),
            controlPoint2: point(538, 295, in: rect)
        )
        path.curve(
            to: point(405, 470, in: rect),
            controlPoint1: point(420, 387, in: rect),
            controlPoint2: point(396, 428, in: rect)
        )
        path.curve(
            to: point(489, 572, in: rect),
            controlPoint1: point(414, 516, in: rect),
            controlPoint2: point(448, 545, in: rect)
        )
        path.curve(
            to: point(548, 710, in: rect),
            controlPoint1: point(539, 605, in: rect),
            controlPoint2: point(558, 653, in: rect)
        )
        path.curve(
            to: point(442, 868, in: rect),
            controlPoint1: point(538, 766, in: rect),
            controlPoint2: point(476, 816, in: rect)
        )
        path.line(to: point(194, 868, in: rect))
        path.curve(
            to: point(160, 834, in: rect),
            controlPoint1: point(175, 868, in: rect),
            controlPoint2: point(160, 853, in: rect)
        )
        path.line(to: point(160, 182, in: rect))
        path.curve(
            to: point(194, 148, in: rect),
            controlPoint1: point(160, 163, in: rect),
            controlPoint2: point(175, 148, in: rect)
        )
        path.close()
        return path
    }

    private static func rightPanel(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(660, 148, in: rect))
        path.line(to: point(830, 148, in: rect))
        path.curve(
            to: point(864, 182, in: rect),
            controlPoint1: point(849, 148, in: rect),
            controlPoint2: point(864, 163, in: rect)
        )
        path.line(to: point(864, 834, in: rect))
        path.curve(
            to: point(830, 868, in: rect),
            controlPoint1: point(864, 853, in: rect),
            controlPoint2: point(849, 868, in: rect)
        )
        path.line(to: point(537, 868, in: rect))
        path.curve(
            to: point(640, 716, in: rect),
            controlPoint1: point(568, 824, in: rect),
            controlPoint2: point(629, 777, in: rect)
        )
        path.curve(
            to: point(581, 578, in: rect),
            controlPoint1: point(650, 659, in: rect),
            controlPoint2: point(631, 610, in: rect)
        )
        path.curve(
            to: point(494, 477, in: rect),
            controlPoint1: point(539, 551, in: rect),
            controlPoint2: point(503, 524, in: rect)
        )
        path.curve(
            to: point(570, 350, in: rect),
            controlPoint1: point(486, 432, in: rect),
            controlPoint2: point(512, 392, in: rect)
        )
        path.curve(
            to: point(660, 148, in: rect),
            controlPoint1: point(631, 306, in: rect),
            controlPoint2: point(660, 260, in: rect)
        )
        path.close()
        return path
    }

    private static func point(_ sourceX: CGFloat, _ sourceY: CGFloat, in rect: NSRect) -> NSPoint {
        let inset = min(rect.width, rect.height) / 9
        let drawingBounds = rect.insetBy(dx: inset, dy: inset)
        let normalizedX = (sourceX - 160) / (864 - 160)
        let normalizedY = (868 - sourceY) / (868 - 148)
        return NSPoint(
            x: drawingBounds.minX + normalizedX * drawingBounds.width,
            y: drawingBounds.minY + normalizedY * drawingBounds.height
        )
    }
}
