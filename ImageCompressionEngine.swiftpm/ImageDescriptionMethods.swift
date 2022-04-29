//
//  File.swift
//  ImageCompressionEngine
//
//  Created by Eskil Sviggum on 02/04/2022.
//

import UIKit
import simd

//MARK: Static methods
extension GenericImageDescription {
    static func fromUIImage(_ image: UIImage, size: Int?=nil, copy: Bool=false) -> ImageDescription? {
        if let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        {
            if copy {
                let cnt = cgImage.width*cgImage.height*4
                let src = UnsafeMutablePointer<UInt8>.allocate(capacity: cnt)
                copyMemory(dest: src, source: bytes, count: cnt)
                return ImageDescription(bytes: src, width: size ?? cgImage.width, height: size ?? cgImage.height, channels: 4)
            }else {
                return ImageDescription(bytes: UnsafeMutablePointer(mutating: bytes), width: size ?? cgImage.width, height: size ?? cgImage.height, channels: 4)
            }
        }
        else { return nil }
    }
}

//MARK: ImageDescription (UInt8)
extension GenericImageDescription where T == UInt8 {
    
    func extractLuma() -> ImageDescription {
        if self.channels == 1 { return self }
        else if self.channels < 3 || self.channels > 4 { fatalError("Image description must have 1, 3, or 4 channels to extract luma") }
        
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 1 * self.count())
        for i in 0..<self.count() {
            let idx = self.channels * i
            let r = self.bytes[idx + 0]
            let g = self.bytes[idx + 1]
            let b = self.bytes[idx + 2]
            let luma = biHexconeLuma(r: r, g: g, b: b)
            bytes[i] = luma
        }
        return ImageDescription(bytes: bytes, width: self.width, height: self.height, channels: 1)
    }

    func extractYCbCr() -> FloatingImageDescription {
        if self.channels < 3 || self.channels > 4 { fatalError("Image description must have 1, 3, or 4 channels to extract components") }
        
        let conversion = simd_float3x3(rows: [SIMD3(x: 0.2126,y: 0.7152,z: 0.0722),
                                              SIMD3(x: -0.1146,y: -0.3854,z: 0.5),
                                              SIMD3(x: 0.5,y: -0.4542,z: -0.0458)])
        
        let bytes = UnsafeMutablePointer<Float>.allocate(capacity: 3 * self.count())
        for i in 0..<self.count() {
            let idx = self.channels * i
            let r = self.bytes[idx + 0]
            let g = self.bytes[idx + 1]
            let b = self.bytes[idx + 2]
            
            let rgb = SIMD3<Float>(x: Float(r), y: Float(g), z: Float(b))
            let yCbCr = conversion * rgb
            
            bytes[3*i + 0] = yCbCr.x
            bytes[3*i + 1] = yCbCr.y + 128
            bytes[3*i + 2] = yCbCr.z + 128
        }
        return FloatingImageDescription(bytes: bytes, width: self.width, height: self.height, channels: 3)
    }
    
    func convertToRGBA() -> ImageDescription {
        let c = self.channels
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 4 * self.count())
        for i in 0..<self.count() {
            let oldIdx = self.channels * i
            let newIdx = 4 * i
            bytes[newIdx + 0] = self.bytes[oldIdx + 0]
            bytes[newIdx + 1] = c < 2 ? bytes[newIdx + 0] : self.bytes[oldIdx + 1]
            bytes[newIdx + 2] = c < 3 ? bytes[newIdx + 1] : self.bytes[oldIdx + 2]
            bytes[newIdx + 3] = c < 4 ? 255 : self.bytes[oldIdx + 3]
        }
        return ImageDescription(bytes: bytes, width: self.width, height: self.height, channels: 4)
    }

    func toUIImage() -> UIImage? {
        if self.channels != 4 { fatalError("Image description must have exactly 4 channels (RGBA).") }
        guard let cgImage = createImageFromRGBABuffer(self.bytes, width: self.width, height: self.height) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    func toFloating() -> FloatingImageDescription {
        let bytes = UnsafeMutablePointer<Float>.allocate(capacity: self.channels*self.count())
        
        for i in 0..<self.channels*self.count() {
            let value = Float(self.bytes[i])
            bytes[i] = value
        }
        
        return FloatingImageDescription(bytes: bytes, width: self.width, height: self.height, channels: self.channels)
    }
    
}

//MARK: FloatingImageDescription (Float)
extension GenericImageDescription where T == Float {
    
    func reconstructWithYCbCrComponents() -> ImageDescription {
        if self.channels != 3 { fatalError("Image description must have 3 channels to extract components") }
        
        let conversion = simd_float3x3(rows: [SIMD3(x: 1, y: 0, z: 1.5748),
                                              SIMD3(x: 1, y: -0.1873, z: -0.4681),
                                              SIMD3(x: 1, y: 1.8556, z: 0)])
        
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 4 * self.count())
        for i in 0..<self.count() {
            let idx = self.channels * i
            let Y = self.bytes[idx + 0]
            let Cb = self.bytes[idx + 1]
            let Cr = self.bytes[idx + 2]
            
            let YCbCr = SIMD3<Float>(x: Y, y: Cb - 128, z: Cr - 128)
            let rgb = clamp(conversion * YCbCr, min: 0, max: 255)
            
            bytes[4*i + 0] = UInt8(rgb.x)
            bytes[4*i + 1] = UInt8(rgb.y)
            bytes[4*i + 2] = UInt8(rgb.z)
            bytes[4*i + 3] = 255
        }
        return ImageDescription(bytes: bytes, width: self.width, height: self.height, channels: 4)
    }

    func replaceLuma(luma: ImageDescription) {
        if self.channels != 3 { fatalError("Image description must have 3 channels to insert luma") }
        if luma.channels != 1 { fatalError("Luma must have 1 channels") }
        if luma.count() != self.count() { fatalError("The two arguments must have equal area") }
        
        for i in 0..<luma.count() {
            let fLuma = Float(luma.bytes[i])
            self.bytes[3*i + 0] = fLuma
        }
    }

    func extractLumaFromImageComponents() -> FloatingImageDescription {
        if self.channels != 3 { fatalError("Image description must have 3 channels to insert luma") }
        let bytes = UnsafeMutablePointer<Float>.allocate(capacity: 1 * self.count())
        
        for i in 0..<self.count() {
            let fLuma = self.bytes[3*i + 0]
            bytes[i] = fLuma
        }
        
        return FloatingImageDescription(bytes: bytes, width: self.width, height: self.height, channels: 1)
    }

    func chromaSubsampleWithImageComponents(segmentSize: Int = 3, type: SubsampleType = .first) {
        switch type {
        case.first:     self.chromaSubsampleFirst(segmentSize: segmentSize)
        case.average:   self.chromaSubsampleAvg(segmentSize: segmentSize)
        }
    }

    func chromaSubsampleFirst(segmentSize: Int = 3) {
        if self.channels != 3 { fatalError("Image description must have 3 channels to extract components") }
        
        let numKols = self.width / segmentSize
        let numRows = self.height / segmentSize
        let area = numKols*numRows
        
        let bytes = self.bytes
        for j in 0..<area {
            let row = j / numKols
            let col = j % numKols
            let i = row*self.width + col
            let idx = self.channels * i
            
            let Cb: Float = self.bytes[idx*segmentSize + 1],
                Cr: Float = self.bytes[idx*segmentSize + 2]
        
            for y in 0..<segmentSize {
                for x in 0..<segmentSize {
                    let indx = self.channels * (i*segmentSize + (y*self.width + x))
                    bytes[indx + 1] = Cb
                    bytes[indx + 2] = Cr
                }
            }
        }
    }

    func chromaSubsampleAvg(segmentSize: Int = 3) {
        if self.channels != 3 { fatalError("Image description must have 3 channels to extract components") }
        
        let numKols = self.width / segmentSize
        let numRows = self.height / segmentSize
        let area = numKols*numRows
        
        let bytes = self.bytes
        for j in 0..<area {
            let row = j / numKols
            let col = j % numKols
            let i = row*self.width + col
            
            var Cb: Float = 0,
                Cr: Float = 0
            
            let segmArea = Float(segmentSize*segmentSize)
            
            for y in 0..<segmentSize {
                for x in 0..<segmentSize {
                    let indx = self.channels * (i*segmentSize + (y*self.width + x))
                    Cb += self.bytes[indx + 1]
                    Cr += self.bytes[indx + 2]
                }
            }
            
            for y in 0..<segmentSize {
                for x in 0..<segmentSize {
                    let indx = self.channels * (i*segmentSize + (y*self.width + x))
                    bytes[indx + 1] = Cb / segmArea
                    bytes[indx + 2] = Cr / segmArea
                }
            }
        }
    }
    
    func toIntegral(offset: Float = 0) -> ImageDescription {
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: self.channels*self.count())
        
        for i in 0..<self.channels*self.count() {
            let val = self.bytes[i] + offset
            let value = UInt8(clamp(val, min: 0, max: 255))
            bytes[i] = value
        }
        
        return ImageDescription(bytes: bytes, width: self.width, height: self.height, channels: self.channels)
    }
    
    func toIntegralNonclamping(offset: Float = 0) -> ImageDescription {
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: self.channels*self.count())
        
        for i in 0..<self.channels*self.count() {
            let val = self.bytes[i] + offset
            let value = UInt8(val)
            bytes[i] = value
        }
        
        return ImageDescription(bytes: bytes, width: self.width, height: self.height, channels: self.channels)
    }
    
    func toInt16Buffer(offset: Float = 0) -> UnsafePointer<Int16> {
        if self.channels != 1 { fatalError("Must only have one channel.") }
        let bytes = UnsafeMutablePointer<Int16>.allocate(capacity: self.count())
        
        let max = Float(Int16.max)
        
        for i in 0..<self.count() {
            let val = self.bytes[i] + offset
            let value = Int16(clamp(val, min: -max, max: max))
            bytes[i] = value
        }
        
        return UnsafePointer(bytes)
    }
    
    func shiftAroundZero() -> FloatingImageDescription {
        let bytes = UnsafeMutablePointer<Float>.allocate(capacity: self.channels * self.count())
        for i in 0..<self.channels*self.count() { bytes[i] = self.bytes[i] - 128 }
        return FloatingImageDescription(bytes: bytes, width: self.width, height: self.height, channels: self.channels)
    }
    
    func quantizeWithDithering(colormap: UnsafePointer<Float>, numColors: Int) {
        let w = self.width
        for i in 0..<self.count() {
            let idx = self.channels * i
            let rgb = SIMD3<Float>(x: self.bytes[idx + 0], y: self.bytes[idx + 1], z: self.bytes[idx + 2])
            
            var bestFit = Float.infinity
            var match: SIMD3<Float>!
            
            for i in 0..<numColors {
                let ix = self.channels * i
                let rgbMatch = SIMD3<Float>(x: colormap[ix + 0], y: colormap[ix + 1], z: colormap[ix + 2])
                
                let dist = length_squared(rgbMatch - rgb)
                if dist < bestFit {
                    match = rgbMatch
                    bestFit = dist
                }
            }
            
            let error = rgb - match
            
            let offsets:[(off: Int, scale:Float)] = [(1, 7/16), (w-1, 3/16), (w, 5/16), (w+1, 1/16)]

            for (offset, scale) in offsets {
                self.bytes[offset + idx + 0] += scale * error.x
                self.bytes[offset + idx + 1] += scale * error.y
                self.bytes[offset + idx + 2] += scale * error.z
            }
            
            self.bytes[idx + 0] = match.x
            self.bytes[idx + 1] = match.y
            self.bytes[idx + 2] = match.z
        }
    }
    
    /// Performs a DCT2D algorithm on the image.
    func convertToFrequencyDomain(segmentSize: Int = 8, lut: UnsafePointer<Float>) -> FloatingImageDescription {
        let bytes = UnsafeMutablePointer<Float>.allocate(capacity: self.count())
        
        for i in 0..<self.count() { bytes[i] = self.bytes[i] - 128 }
        
        let segsPerRow = self.width / segmentSize
        let numSegments = segsPerRow * (self.height / segmentSize)
        
        for seg in 0..<numSegments {
            let x = seg % segsPerRow
            let y = Int(floor(Float(seg) / Float(segsPerRow)))
            
            dct2D(bytes, lut: lut, width: self.width, height: self.height, x: x, y: y, segmSize: segmentSize, numSegments: numSegments)
        }
        
        return FloatingImageDescription(bytes: bytes, width: self.width, height: self.height, channels: 1)
    }
    
    /// Performs an inverse DCT2D algorithm on the image.
    func convertToImageDomain(segmentSize: Int = 8, lut: UnsafePointer<Float>) -> ImageDescription {
        let bytes = UnsafeMutablePointer<Float>(mutating: self.bytes)
        
        let segsPerRow = self.width / segmentSize
        let numSegments = segsPerRow * (self.height / segmentSize)
        
        for seg in 0..<numSegments {
            let x = seg % segsPerRow
            let y = Int(floor(Float(seg) / Float(segsPerRow)))
            
            dct2DInv(bytes, lut: lut, width: self.width, height: self.height, x: x, y: y, segmSize: segmentSize)
        }
        
        let result = UnsafeMutablePointer<UInt8>.allocate(capacity: 1 * self.count())
        for i in 0..<self.count() {
            result[i] = UInt8(clamping: Int(abs(bytes[i]+128)))
        }
        
        return ImageDescription(bytes: result, width: self.width, height: self.height, channels: 1)
    }
    
    func performCompression(threshold: Int, segmentSize: Int = 8) -> FloatingImageDescription {
        let bytes = UnsafeMutablePointer<Float>.allocate(capacity: self.count())
        copyMemory(dest: bytes, source: self.bytes, count: self.count())
        
        let segmentArea = segmentSize*segmentSize
        let segsPerRow = self.width / segmentSize
        let numSegments = segsPerRow * (self.height / segmentSize)
        
        let block = UnsafeMutablePointer<Float>.allocate(capacity: segmentArea)
        
        for seg in 0..<numSegments {
            let x = seg % segsPerRow
            let y = seg / segsPerRow
            let xOff = segmentSize * x
            let yOff = segmentSize * y
            
            copyBlockInv(toBytes: block, fromBytes: bytes, offsetX: xOff, offsetY: yOff, size: segmentSize, bWidth: self.width, bHeight: self.height)
            compressionRemoveFromEnd(block: block, threshold: threshold, segmentArea: segmentArea)
            copyBlock(toBytes: bytes, fromBytes: block, offsetX: xOff, offsetY: yOff, size: segmentSize, bWidth: self.width, bHeight: self.height)
        }
        
        block.deallocate()
        
        return FloatingImageDescription(bytes: bytes, width: self.width, height: self.height, channels: 1)
    }
    
    /// Creates a map of the colors used in the image. Runtime: O(N^2)
    func createColormap(numColors: Int, grayscale: Bool=false) -> UnsafeMutablePointer<Float> {
        if self.channels != 3 && self.channels != 4 {fatalError("The image needs 3 or 4 channels to extract a colormap") }
        
        if grayscale {
            return createGrayscalePallet(numColors: numColors)
        }
        
        var result = [SIMD2<Float>: Int]()
        
        for i in 0..<self.count() {
            let idx = self.channels * i
            
            let cb = floor(self.bytes[idx + 1]), cr = floor(self.bytes[idx + 2])
            let simd = SIMD2(x: cb, y: cr)
            result[simd] = i
        }
        var colors = result.sorted { n1, n2 in
            n1.value < n2.value
        }.map { $0.key }
        
        if numColors > colors.count {
            for _  in 0..<(numColors-colors.count) {
                colors.append(SIMD2<Float>(0, 0))
            }
        }
        
        let totalNumColors = Float(colors.count)
        let stride = Int(floor(totalNumColors / min(Float(numColors), totalNumColors)))
        
        let resultBytes = UnsafeMutablePointer<Float>.allocate(capacity: 2*numColors)
        for (i) in 0..<numColors {
            let color = colors[i*stride]
            
            let idx = 2 * i
            resultBytes[idx + 0] = color.x
            resultBytes[idx + 1] = color.y
        }
        
        return resultBytes
    }
    
    func createGrayscalePallet(numColors: Int) -> UnsafeMutablePointer<Float> {
        let totalNumColors:Float = 256
        let resultBytes = UnsafeMutablePointer<Float>.allocate(capacity: 3*numColors)
        let stride = floor(totalNumColors / min(Float(numColors), totalNumColors))
        
        for i in 0..<numColors {
            let val = (Float(i)*stride)
            resultBytes[3*i + 0] = val
            resultBytes[3*i + 1] = val
            resultBytes[3*i + 2] = val
        }
        return resultBytes
    }
    
    func quantizeImageInPlaceMetal(colormap: UnsafePointer<Float>, numColors: Int) {
        return metal_quantizeImage(self, colormap: colormap, numColors: numColors)
    }
    
    func quantizeImageDitheringInPlaceMetal(colormap: UnsafePointer<Float>, numColors: Int, dithermap: UnsafePointer<UInt8>, dithermapSize: Int) {
        return metal_quantizeImageDither(self, colormap: colormap, numColors: numColors, dithermap: dithermap, dithermapSize: dithermapSize)
    }
    
    
    func convertToFrequencyDomainMetal(segmentSize: Int = 8, lut: UnsafePointer<Float>) -> FloatingImageDescription {
        return metal_convertToFrequencyDomainDCTSegm(self, segmentSize: segmentSize, lut: lut)
    }
    
    func convertToImageDomainMetal(segmentSize: Int = 8, lut: UnsafePointer<Float>) -> ImageDescription {
        return metal_convertToImageDomainDCTSegm(self, segmentSize: segmentSize, lut: lut)
    }
    
    func chromaSubsampleMetal(segmentSize: Int, type: SubsampleType = .first, shouldPixelate:Bool = false) -> FloatingImageDescription {
        return metal_chromaSubsample(self, segmentSize: segmentSize, type: type, shouldPixelate: shouldPixelate)
    }
    
    func reconstructWithImageComponentsMetal(shouldIncludeAlpha: Bool=true) -> ImageDescription {
        return metal_reconstructWithImageComponents(self, shouldIncludeAlpha: shouldIncludeAlpha)
    }
}
