//
//  File.swift
//  ImageCompressionEngine
//
//  Created by Eskil Sviggum on 02/04/2022.
//

import SwiftUI
import CoreImage

func copyMemory<T>(dest: UnsafeMutablePointer<T>, source: UnsafePointer<T>, count: Int, dstOffset: Int = 0, srcOffset: Int = 0, dstStride: Int=1, srcStride: Int = 1) {
    for i in 0..<count { dest[i*dstStride + dstOffset] = source[i*srcStride + srcOffset] }
}

func copyBlock<T>(toBytes to: UnsafeMutablePointer<T>, fromBytes from: UnsafePointer<T>, offsetX: Int, offsetY: Int, size: Int, bWidth: Int, bHeight: Int) {
    for row in 0..<size {
        let fromIdx = row*size
        let toIdx = (offsetY+row)*bWidth + offsetX
        copyMemory(dest: to.advanced(by: toIdx), source: from.advanced(by: fromIdx), count: size)
    }
}

func copyBlockInv<T>(toBytes to: UnsafeMutablePointer<T>, fromBytes from: UnsafePointer<T>, offsetX: Int, offsetY: Int, size: Int, bWidth: Int, bHeight: Int) {
    for row in 0..<size {
        let fromIdx = row*size
        let toIdx = (offsetY+row)*bWidth + offsetX
        copyMemory(dest: to.advanced(by: fromIdx), source: from.advanced(by: toIdx), count: size)
    }
}

func compressionRemoveFromEnd(block: UnsafeMutablePointer<Float>, threshold: Int, segmentArea: Int) {
    for i in 0..<min(segmentArea, threshold) { block[segmentArea-i-1] = 0 }
}

extension UIImage {
    func cropping(to rect: CGRect) -> UIImage? {

        if let cgCrop = cgImage?.cropping(to: rect) {
            return UIImage(cgImage: cgCrop)
        }
        else if let ciCrop = ciImage?.cropped(to: rect) {
            return UIImage(ciImage: ciCrop)
        }

        return nil
    }
    
    func resize(to targetSize: CGSize) -> UIImage {
        if targetSize.width == size.width && targetSize.height == size.height { return self }
        
        let scale: CGFloat = self.scale
        let actualTargetSize = CGSize(width: targetSize.width / scale, height: targetSize.height / scale)
        
        let renderer = UIGraphicsImageRenderer(size: actualTargetSize)

        let scaledImage = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: actualTargetSize))
        }
        
        return scaledImage
    }
    
    func blur(radius: CGFloat) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        let context = CIContext()
        let input = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: "inputRadius")
        guard let result = filter.value(forKey: kCIOutputImageKey) as? CIImage,
              let resCG = context.createCGImage(result, from: input.extent)
        else { return nil }
        return UIImage(cgImage: resCG)
    }
}

func createMergedImage(left: UIImage, right: UIImage, progress: CGFloat, size: CGSize, isRunning: Bool, renderSize: CGSize, imageFrame: CGRect) -> UIImage? {
    var leftWidth = floor(progress*size.width)
    if progress >= 1 { leftWidth -= 1 }
    let rightWidth = size.width - leftWidth
    
    guard var rightCropped = right.cropping(to: CGRect(x: leftWidth, y: 0, width: rightWidth, height: size.height))
    else { return nil }
    
    if isRunning {
        rightCropped = rightCropped.blur(radius: 5) ?? rightCropped
    }
    
    let renderer = UIGraphicsImageRenderer(size: size)

    let result = renderer.image { _ in
        left.draw(at: .zero)
        rightCropped.draw(at: CGPoint(x: leftWidth, y: 0))
    }
    
    return renderImageInPlace(result, renderSize: renderSize, imageFrame: imageFrame)
}

func renderImageInPlace(_ image: UIImage, renderSize: CGSize, imageFrame: CGRect) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: renderSize)
    
    let frame = CGRect(x: imageFrame.minX - imageFrame.width / 2, y: imageFrame.minY - imageFrame.height / 2, width: imageFrame.width, height: imageFrame.height)
    
    let result = renderer.image { _ in
        image.draw(in: frame)
    }
    
    return result
}

func convertColorspace(ofImage image: UIImage, toColorSpace colorSpace: CGColorSpace) -> UIImage {
    let rect = CGRect(origin: .zero, size: image.size)
    let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
    let context = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)!
    context.draw(image.cgImage!, in: rect)
    let image = context.makeImage()!
    return UIImage(cgImage: image)
}

func createImageFromRGBABuffer(_ buffer: UnsafePointer<UInt8>, width: Int, height: Int) -> CGImage? {
    let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let mutableRaw = UnsafeMutableRawPointer(mutating: buffer)
    
    let context = CGContext(data: mutableRaw,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: 4*width,
                            space: colorSpace,
                            bitmapInfo: bitmapInfo.rawValue)
    
    let img = context?.makeImage()
    return img
}

func biHexconeLuma(r: UInt8, g: UInt8, b: UInt8) -> UInt8 {
    let maxComp = max(max(r, g), b)
    let minComp = min(min(r, g), b)
    return UInt8((UInt(maxComp) + UInt(minComp)) / 2)
}

func biHexconeLuma<T: BinaryFloatingPoint>(r: T, g: T, b: T) -> T  {
    let maxComp = max(max(r, g), b)
    let minComp = min(min(r, g), b)
    return (maxComp + minComp) / 2
}

func clamp(_ x:Float, min mi: Float, max ma: Float) -> Float {
    return min(ma, max(mi, x))
}

func createRadialMaskLUT(segmentArea: Int, divisor: Int) -> UnsafePointer<Float> {
    let N = segmentArea / divisor
    let bytes = UnsafeMutablePointer<Float>.allocate(capacity: 2*N)
    let arg = .pi*2/Float(segmentArea)
    for i in 0..<N {
        let x = cos(arg*Float(i))
        let y = sin(arg*Float(i))
        bytes[2*i + 0] = x
        bytes[2*i + 1] = y
    }
    return UnsafePointer(bytes)
}

func binding<T>(_ variable: State<T>, withChangeHandler handler: @escaping (T)->Void, transformHandler: ((T)->T)?=nil, initialValue: T, shouldAnimate: Bool = false) -> Binding<T> {
    let binding = Binding<T> {
        return variable.wrappedValue
    } set: { new in
        let val = transformHandler?(new) ?? new
        if shouldAnimate {
            withAnimation { 
                variable.wrappedValue = val
            }
        } else {
            variable.wrappedValue = val
        }
        handler(val)
    }

    return binding
}

func makeWhiteNoise(size: Int, min: UInt8=0, max: UInt8=255) -> ImageDescription {
    let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 1*size*size)
    for i in 0..<size*size {
        let random = UInt8.random(in: min...max)
        bytes[i] = random
    }
    return ImageDescription(bytes: bytes, width: size, height: size, channels: 1)
}

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let window = scene?.windows.first
        let uiInsets = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: uiInsets.top, leading: uiInsets.left, bottom: uiInsets.bottom, trailing: uiInsets.right)
    }
}

extension EnvironmentValues {
    
    var safeAreaInsets: EdgeInsets {
        self[SafeAreaInsetsKey.self]
    }
}

struct LengthPreference: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PointPreference: PreferenceKey {
    static var defaultValue: CGPoint { .zero }
    
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

struct FramePreference: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

func floatingBytesToUnsigned(_ input: UnsafePointer<Float>, count: Int, offset: Float = 0) -> UnsafePointer<UInt8> {
    let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    
    for i in 0..<count {
        let val = input[i] + offset
        let value = UInt8(clamp(val, min: 0, max: 255))
        bytes[i] = value
    }
    
    return UnsafePointer(bytes)
}

func unsignedBytesToFloating(_ input: UnsafePointer<UInt8>, count: Int, offset: Float = 0) -> UnsafePointer<Float> {
    let bytes = UnsafeMutablePointer<Float>.allocate(capacity: count)
    
    for i in 0..<count {
        let value = Float(input[i]) + offset
        bytes[i] = value
    }
    
    return UnsafePointer(bytes)
}


func documentUrlForFile(withName name: String, storing data: Data) throws -> URL {
    let fs = FileManager.default
    let documentDirectoryUrl = try fs.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let fileUrl = documentDirectoryUrl.appendingPathComponent(name)
    
    try data.write(to: fileUrl)
    
    return fileUrl
}

func removeTemporaryUrlForFile(withName name: String) {
    do {
        let fs = FileManager.default
        let documentDirectoryUrl = try fs.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let filePath = documentDirectoryUrl.appendingPathComponent(name).path
        
        if fs.fileExists(atPath: filePath) { try fs.removeItem(atPath: filePath) }
    } catch {
        print(error)
    }
}
