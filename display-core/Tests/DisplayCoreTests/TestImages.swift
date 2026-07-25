import Foundation
import CoreGraphics
import ImageIO
@testable import DisplayCore

// Generates real image data in-code (via ImageIO) so media tests stay hermetic — no binary fixtures.
enum TestImages {
    static func solidCGImage(width: Int, height: Int, gray: Double = 0.5) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func pngData(width: Int, height: Int) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, solidCGImage(width: width, height: height), nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    static func animatedGIFData(frames: Int, size: Int, delay: Double) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, frames, nil)!
        CGImageDestinationSetProperties(dest,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for i in 0..<frames {
            let frame = solidCGImage(width: size, height: size, gray: Double(i) / Double(frames))
            let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay]]
            CGImageDestinationAddImage(dest, frame, props as CFDictionary)
        }
        CGImageDestinationFinalize(dest)
        return data as Data
    }
}

// A Sendable counter for asserting how many times a stubbed fetch ran.
actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
