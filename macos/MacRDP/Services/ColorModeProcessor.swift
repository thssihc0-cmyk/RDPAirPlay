import AppKit
import CoreGraphics
import Foundation

/// F-DISP-05 / F-WN-07 stub: 客户端侧色彩模式处理（锁色后仍可叠自适应档）
enum ColorModeProcessor {
    static func apply(_ mode: ColorMode, to image: NSImage) -> NSImage {
        guard mode != .fullColor else { return image }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return image }

        let width = cg.width
        let height = cg.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i])
            let g = Double(pixels[i + 1])
            let b = Double(pixels[i + 2])
            let gray = UInt8(min(255, 0.299 * r + 0.587 * g + 0.114 * b))
            if mode == .monochrome {
                let v: UInt8 = gray > 127 ? 255 : 0
                pixels[i] = v
                pixels[i + 1] = v
                pixels[i + 2] = v
            } else {
                pixels[i] = gray
                pixels[i + 1] = gray
                pixels[i + 2] = gray
            }
        }

        guard let out = ctx.makeImage() else { return image }
        return NSImage(cgImage: out, size: NSSize(width: width, height: height))
    }
}
