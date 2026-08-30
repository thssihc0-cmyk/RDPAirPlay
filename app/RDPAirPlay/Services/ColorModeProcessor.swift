import CoreGraphics
import CoreImage
import UIKit

/// F-NET-03 / F-NET-04: 客户端色彩模式处理
enum ColorModeProcessor {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func apply(_ mode: ColorMode, to image: CGImage) -> CGImage? {
        switch mode {
        case .fullColor:
            return image
        case .grayscale:
            return applyFilter(named: "CIColorControls", to: image) { filter in
                filter.setValue(0.0, forKey: kCIInputSaturationKey)
            }
        case .monochrome:
            guard let grayscale = applyFilter(named: "CIColorControls", to: image, configure: { filter in
                filter.setValue(0.0, forKey: kCIInputSaturationKey)
                filter.setValue(1.2, forKey: kCIInputContrastKey)
            }) else { return nil }
            return applyFilter(named: "CIColorMonochrome", to: grayscale) { filter in
                filter.setValue(CIColor(red: 1, green: 1, blue: 1), forKey: kCIInputColorKey)
                filter.setValue(1.0, forKey: kCIInputIntensityKey)
            }
        }
    }

    private static func applyFilter(
        named name: String,
        to image: CGImage,
        configure: (CIFilter) -> Void
    ) -> CGImage? {
        guard let filter = CIFilter(name: name) else { return image }
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        configure(filter)
        guard let output = filter.outputImage,
              let result = context.createCGImage(output, from: output.extent) else {
            return image
        }
        return result
    }
}
