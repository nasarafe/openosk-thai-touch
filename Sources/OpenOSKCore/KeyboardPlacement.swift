import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Places a floating keyboard near a field using AppKit (bottom-left) coordinates.
public enum KeyboardPlacement {
    public static func origin(near field: CGRect, keyboardSize: CGSize,
                              visibleFrame: CGRect) -> CGPoint {
        let margin: CGFloat = 12
        let available = visibleFrame.insetBy(dx: margin, dy: margin)
        let width = keyboardSize.width
        let height = keyboardSize.height
        let x = min(max(field.midX - width / 2, available.minX),
                    max(available.minX, available.maxX - width))
        let below = CGPoint(x: x, y: field.minY - margin - height)
        if below.y >= available.minY { return below }
        let above = CGPoint(x: x, y: field.maxY + margin)
        if above.y + height <= available.maxY { return above }
        // Tall editors may span the screen. Prefer a side if one is free.
        let y = min(max(field.midY - height / 2, available.minY),
                    max(available.minY, available.maxY - height))
        if field.maxX + margin + width <= available.maxX {
            return CGPoint(x: field.maxX + margin, y: y)
        }
        if field.minX - margin - width >= available.minX {
            return CGPoint(x: field.minX - margin - width, y: y)
        }
        // No placement can avoid a screen-sized field: keep the keyboard visible.
        return CGPoint(x: x, y: available.minY)
    }
}
