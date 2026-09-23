import AppKit
import CoreGraphics
import Foundation

enum RDPFrameConverter {
    /// FreeRDP GDI 常见为 BGRA；转为 NSImage
    static func image(fromBGRA data: Data, width: Int, height: Int, stride: Int) -> NSImage? {
        guard width > 0, height > 0, stride >= width * 4, data.count >= stride * height else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for y in 0..<height {
                let srcRow = base.advanced(by: y * stride)
                for x in 0..<width {
                    let si = x * 4
                    let di = (y * width + x) * 4
                    rgba[di] = srcRow[si + 2]
                    rgba[di + 1] = srcRow[si + 1]
                    rgba[di + 2] = srcRow[si]
                    rgba[di + 3] = srcRow[si + 3]
                }
            }
        }

        let bytesPerRow = width * 4
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cg = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }

        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }
}
