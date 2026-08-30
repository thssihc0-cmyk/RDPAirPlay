import CoreGraphics
import Foundation
import UIKit

enum RDPFrameConverter {
    private static let opaqueDesktopBitmapInfo = CGBitmapInfo.byteOrder32Little
        .union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue))

    private static let cursorBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)

    static func image(from frame: rdp_bridge_frame) -> UIImage? {
        makeImage(
            pixels: frame.pixels,
            width: Int(frame.width),
            height: Int(frame.height),
            stride: frame.stride > 0 ? Int(frame.stride) : Int(frame.width) * 4,
            bitmapInfo: opaqueDesktopBitmapInfo
        )
    }

    static func cursorImage(from cursor: rdp_bridge_cursor) -> UIImage? {
        guard cursor.has_image != 0, cursor.width > 0, cursor.height > 0, cursor.pixels != nil else {
            return nil
        }
        return makeImage(
            pixels: cursor.pixels,
            width: Int(cursor.width),
            height: Int(cursor.height),
            stride: cursor.stride > 0 ? Int(cursor.stride) : Int(cursor.width) * 4,
            bitmapInfo: cursorBitmapInfo
        )
    }

    private static func makeImage(
        pixels: UnsafePointer<UInt8>?,
        width: Int,
        height: Int,
        stride: Int,
        bitmapInfo: CGBitmapInfo
    ) -> UIImage? {
        guard width > 0, height > 0, let pixels else { return nil }
        let dataSize = stride * height
        let buffer = Data(bytes: pixels, count: dataSize)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let provider = CGDataProvider(data: buffer as CFData) else { return nil }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: stride,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
