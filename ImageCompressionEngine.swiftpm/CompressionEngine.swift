//
//  CompressionEngine.swift
//  ImageCompressionEngine
//
//  Created by Eskil Sviggum on 02/04/2022.
//

import SwiftUI
import Compression

struct CompressionEngine {
    let descriptions = ImageDescriptions()
    
    let originalImage = ValueManager<UIImage>()
    let compressedImage = ValueManager<UIImage>()
    
    let compressionPageSize: Int = 1024
    let headerSize = 10
    
    class ImageDescriptions {
        var frequencyDomain: FloatingImageDescription?
        var compressedFrequencyDomain: UnsafePointer<Int16>?
        var compressedLuma: ImageDescription?
        
        var YCbCr: FloatingImageDescription?
        var luma: FloatingImageDescription?
        
        var finalImage: FloatingImageDescription?
        var subsampledYCbCr: FloatingImageDescription?
        
        var dctLUT: UnsafePointer<Float>?
        
        var lutSize: Int = 8
        var subsampleSize: Int = 1
        var Ndct: Int = 64
        var isGrayscale: Bool = false
        var colormap: UnsafePointer<UInt8>?
        var numColors: Int?
        
        let dithermap: UnsafeMutablePointer<UInt8>
        let dithersize: Int
        
        init() {
            let size = 64
            let imageDesc = makeWhiteNoise(size: size, min: 100, max: 200)
            dithermap = imageDesc.bytes
            dithersize = size
        }
    }
}

extension CompressionEngine {
    
    //MARK: Create new lut
    func createNewLUT(forSegmentSize segmentSize: Int) {
        self.descriptions.lutSize = segmentSize
        self.descriptions.dctLUT = createDiscreteCosineLUT(count: segmentSize)
    }
    
    //MARK: Handle new image
    func handleNewImage(_ image: UIImage, size: CGFloat = 400) {
        // Crop and resize image to size x size (square)
        let maxSize = min(image.size.width, image.size.height)
        var resized = image
            .cropping(to: CGRect(x: 0, y: 0, width: maxSize, height: maxSize))!
            .resize(to: CGSize(width: size, height: size))
        let colorSpace =  CGColorSpaceCreateDeviceRGB()
        resized = convertColorspace(ofImage: resized, toColorSpace: colorSpace)
        
        // Release memory
        self.descriptions.YCbCr?.release()
        self.descriptions.luma?.release()
        
        // Extract color and luma
        guard let desc = ImageDescription.fromUIImage(resized, size: Int(size)) else { return }
        self.descriptions.YCbCr = desc.extractYCbCr()
        self.descriptions.luma = self.descriptions.YCbCr!.extractLumaFromImageComponents()
        
        self.originalImage.value = resized
    }
    
    func handleImportedImage(yCbCr: FloatingImageDescription) {
        // Release memory
        self.descriptions.YCbCr?.release()
        self.descriptions.luma?.release()
        
        self.descriptions.YCbCr = yCbCr
        self.descriptions.luma = yCbCr.extractLumaFromImageComponents()
        let resImg = yCbCr.reconstructWithImageComponentsMetal()
        self.originalImage.value = resImg.toUIImage()
        resImg.release()
    }
    
    func startCompositing() {
        self.descriptions.finalImage = self.descriptions.YCbCr!.createCopy()
    }
    
    //MARK: Process DCT
    
    func processDCT(luma: FloatingImageDescription, segmentSize: Int) {
        guard let dctLUT = self.descriptions.dctLUT else { return }
        
        if segmentSize >= 100 {
            self.descriptions.frequencyDomain = luma.convertToFrequencyDomain(segmentSize: segmentSize, lut: dctLUT)
        } else {
            self.descriptions.frequencyDomain = luma.convertToFrequencyDomainMetal(segmentSize: segmentSize, lut: dctLUT)
        }
    }
    
    func compressImage(luma: FloatingImageDescription, threshold: Float, segmentSize: Int) {
        guard let lut = self.descriptions.dctLUT else { return }
        
        let thresh = Int(threshold * Float(segmentSize*segmentSize))
        let modDCT = luma.performCompression(threshold: thresh, segmentSize: segmentSize)
        self.descriptions.compressedFrequencyDomain = modDCT.toInt16Buffer()
        
        if segmentSize >= 100 {
            self.descriptions.compressedLuma = modDCT.convertToImageDomain(segmentSize: segmentSize, lut: lut)
        } else {
            self.descriptions.compressedLuma = modDCT.convertToImageDomainMetal(segmentSize: segmentSize, lut: lut)
        }
        
        modDCT.release()
        
        self.descriptions.finalImage!.replaceLuma(luma: self.descriptions.compressedLuma!)
    }
    
    func subsampleImage(yCbCr: FloatingImageDescription, segmentSize: Int) {
        self.descriptions.finalImage = yCbCr.chromaSubsampleMetal(segmentSize: segmentSize, type: .average)
    }
    
    func quantizeImage(yCbCr: FloatingImageDescription, numColors: Int, shouldDither: Bool, grayscale: Bool) {
        let colormap = yCbCr.createColormap(numColors: numColors, grayscale: grayscale)
        
        if shouldDither {
            yCbCr.quantizeImageDitheringInPlaceMetal(colormap: colormap, numColors: numColors, dithermap: self.descriptions.dithermap, dithermapSize: self.descriptions.dithersize)
        } else {
            yCbCr.quantizeImageInPlaceMetal(colormap: colormap, numColors: numColors)
        }
        self.descriptions.colormap = floatingBytesToUnsigned(colormap, count: 2 * numColors)
        colormap.deallocate()
    }
    
    func renderCompressedImage() {
        guard let finalImage = self.descriptions.finalImage else { return }
        let rgbaDesc = finalImage.reconstructWithImageComponentsMetal()
        let image = rgbaDesc.toUIImage()
        self.compressedImage.value = image
        rgbaDesc.release()
    }
    
    func performFullCompression(thresold: Float, segmentSize: Int, subsampleSize: Int, numColors: Int, shouldDither: Bool, shouldMakeGrayscalePallet: Bool, generateDCT: Bool = true, shouldQuantize: Bool = false) {
        
        startCompositing()
        let desc = self.descriptions
        
        // Luma
        if generateDCT || desc.lutSize != segmentSize {
            createNewLUT(forSegmentSize: segmentSize)
            self.processDCT(luma: desc.luma!, segmentSize: segmentSize)
        }
        self.compressImage(luma: desc.frequencyDomain!, threshold: thresold, segmentSize: segmentSize)
        let segmentArea = segmentSize*segmentSize
        desc.Ndct = segmentArea - Int(thresold * Float(segmentArea))
        
        // Subsample
        desc.subsampleSize = subsampleSize
        subsampleImage(yCbCr: desc.finalImage!, segmentSize: subsampleSize)
        
        // Quantize
        if shouldQuantize {
            quantizeImage(yCbCr: desc.finalImage!, numColors: numColors, shouldDither: shouldDither, grayscale: false)
            self.descriptions.numColors = numColors
        } else {
            self.descriptions.numColors = nil
        }
        
        self.descriptions.subsampledYCbCr?.release()
        self.descriptions.subsampledYCbCr = self.descriptions.finalImage!.createCopy()
        
        var rgbaDesc: ImageDescription
        if shouldMakeGrayscalePallet {
            self.descriptions.isGrayscale = true
            rgbaDesc = self.descriptions.compressedLuma!.convertToRGBA()
        } else {
            self.descriptions.isGrayscale = false
            rgbaDesc = desc.finalImage!.reconstructWithImageComponentsMetal()
        }
        
        let image = rgbaDesc.toUIImage()
        self.compressedImage.value = image
        rgbaDesc.release()
    }
    
    func createWackImageData() -> Data? {
        let desc = self.descriptions
        guard let yCbCr = desc.subsampledYCbCr,
              let comprLuma = desc.compressedFrequencyDomain
        else { return nil }
        
        let w = yCbCr.width,
            h = yCbCr.height,
            Sdct = desc.lutSize,
            Ncolors = desc.numColors ?? 0,
            isGrayscale = desc.isGrayscale,
            colormap = desc.colormap
        var Scbcr = (desc.subsampleSize)
        
        let hasColormap = (Ncolors != 0)
        let chromaStride = hasColormap ? 1 : 2
        
        let headerSize = self.headerSize
        let lumaSize = 2 * yCbCr.count()
        let chromaSize = chromaStride * yCbCr.count()
        let colormapSize = 2 * Ncolors
        var dataSize = headerSize + lumaSize + colormapSize
        
        if isGrayscale { Scbcr = 0 }
        else { dataSize += chromaSize }
        
        let data = UnsafeMutableRawPointer(UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize))
        
        // Header 
        data.storeBytes(of: UInt16(w),       toByteOffset: 0, as: UInt16.self)
        data.storeBytes(of: UInt16(h),       toByteOffset: 2, as: UInt16.self)
        data.storeBytes(of: UInt16(Sdct),    toByteOffset: 4, as: UInt16.self)
        data.storeBytes(of: UInt16(Scbcr),   toByteOffset: 6, as: UInt16.self)
        data.storeBytes(of: UInt16(Ncolors), toByteOffset: 8, as: UInt16.self)
        
        let ptr = data.advanced(by: headerSize).assumingMemoryBound(to: UInt8.self)
        let int16Ptr = data.advanced(by: headerSize).assumingMemoryBound(to: Int16.self)
        int16Ptr.assign(from: comprLuma, count: yCbCr.count())
        
        var lut: [SIMD2<UInt8>: Int] = [:]
        
        if let colormap = colormap, hasColormap && !isGrayscale {
            for i in 0..<Ncolors {
                let cb = colormap[2 * i + 0]
                let cr = colormap[2 * i + 1]
                
                lut[SIMD2(cb, cr)] = i
            }
            
            ptr.advanced(by: lumaSize + chromaSize).assign(from: colormap, count: colormapSize)
        }
        
        if !isGrayscale {
            for i in 0..<yCbCr.count() {
                let chromaPtr = ptr.advanced(by: lumaSize + chromaStride * i)
                let cb = UInt8(clamping: Int(yCbCr.bytes[3 * i + 1]))
                let cr = UInt8(clamping: Int(yCbCr.bytes[3 * i + 2]))
                
                if hasColormap {
                    if let colormapIndex = lut[SIMD2(cb, cr)] {
                        chromaPtr[0] = UInt8(colormapIndex)
                    } else {
                        chromaPtr[0] = 0
                    }
                } else {
                    chromaPtr[0] = cb
                    chromaPtr[1] = cr
                }
            }
        }
        
        let res = Data(bytes: data, count: dataSize)
        
        return try? compress(data: res)
    }
    
    func importImageWack(fromData compressedData: Data) {
        do {
            let data = try decompress(data: compressedData)
            
            let headerSize = self.headerSize
            data.withUnsafeBytes { buffPtr in
                let bytes = buffPtr.baseAddress!
                let headerBytes = bytes.assumingMemoryBound(to: UInt16.self)
                
                let w = Int(headerBytes.advanced(by: 0).pointee)
                let h = Int(headerBytes.advanced(by: 1).pointee)
                let Sdct = Int(headerBytes.advanced(by: 2).pointee)
                let Scbcr = Int(headerBytes.advanced(by: 3).pointee)
                let Ncolors = Int(headerBytes.advanced(by: 4).pointee)
                
                let isGrayscale = (Scbcr == 0)
                let hasColormap = (Ncolors != 0)
                let chromaStride = hasColormap ? 1 : 2
                
                let imageSize = w * h
                let lumaSize = 2 * imageSize
                let chromaSize = chromaStride * imageSize
                let ptr = bytes.advanced(by: headerSize).assumingMemoryBound(to: UInt8.self)
                let int16Ptr = bytes.advanced(by: headerSize).assumingMemoryBound(to: Int16.self)
                
                let luma = UnsafeMutablePointer<Float>.allocate(capacity: 1 * w * h)
                let ycbcr = UnsafeMutablePointer<Float>.allocate(capacity: 3 * w * h)
                
                for i in 0..<imageSize { luma[i] = Float(int16Ptr[i]) }
                
                let lumaDesc = FloatingImageDescription(bytes: luma, width: w, height: h, channels: 1)
                let dctlut = createDiscreteCosineLUT(count: Sdct)
                let compressedLuma = lumaDesc.convertToImageDomainMetal(segmentSize: Sdct, lut: dctlut)
                
                var colormap: UnsafePointer<UInt8>?
                
                if hasColormap && !isGrayscale { colormap = ptr.advanced(by: lumaSize + chromaSize) }
                
                if !isGrayscale {
                    for i in 0..<imageSize {
                        let chromaPtr = ptr.advanced(by: lumaSize + chromaStride * i)
                        var cb: Float!
                        var cr: Float!
                        if let colormap = colormap {
                            let idx = Int(chromaPtr[0])
                            cb = Float(colormap[2 * idx + 0])
                            cr = Float(colormap[2 * idx + 1])
                        } else {
                            cb = Float(chromaPtr[0])
                            cr = Float(chromaPtr[1])
                        }
                        ycbcr[3 * i + 1] = cb
                        ycbcr[3 * i + 2] = cr
                    }
                } else {
                    for i in 0..<imageSize {
                        ycbcr[3 * i + 1] = 128
                        ycbcr[3 * i + 2] = 128
                    }
                }
                
                let ycbcrDesc = FloatingImageDescription(bytes: ycbcr, width: w, height: h, channels: 3)
                ycbcrDesc.replaceLuma(luma: compressedLuma)
                self.handleImportedImage(yCbCr: ycbcrDesc)
            }
        } catch {
            print(error)
        }
    }
    
    func compress(data input: Data) throws -> Data {
        var dest = Data()
        let outputFilter = try OutputFilter(.compress, using: .lzfse, writingTo: { data in
            if let data = data { dest.append(data) }
        })
        
        var index = 0
        let inputSize = input.count
        let pageSize = self.compressionPageSize
        
        while true {
            let readLength = min(pageSize, inputSize - index)
            
            let subdata = input.subdata(in: index..<index + readLength)
            try outputFilter.write(subdata)
            
            index += readLength
            if readLength == 0 { break }
        }
        
        return dest
    }
    
    func decompress(data input: Data) throws -> Data {
        var dest = Data()
        
        var index = 0
        let inputSize = input.count
        let pageSize = self.compressionPageSize
        
        let inputFilter = try InputFilter<Data>(.decompress, using: .lzfse, readingFrom: { length in
            let readLength = min(length, inputSize - index)
            let subdata = input.subdata(in: index..<index + readLength)
            
            index += readLength
            return subdata
        })
        
        while let page = try inputFilter.readData(ofLength: pageSize) {
            dest.append(page)
        }
        
        return dest
    }
}
