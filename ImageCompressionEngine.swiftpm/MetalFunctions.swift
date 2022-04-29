//
//  File.swift
//  ImageCompressionEngine
//
//  Created by Eskil Sviggum on 02/04/2022.
//

import Metal
import simd

//MARK: Precompiled

struct PrecompiledMetalFunctions {
    let dct2D = precompileMetalFunction(functionName: "dct2D")
    let dct2DInv = precompileMetalFunction(functionName: "dct2DInv")
    let chromaSubsampleFirst = precompileMetalFunction(functionName: "chromaSubsampleFirst")
    let chromaSubsampleAverage = precompileMetalFunction(functionName: "chromaSubsampleAvg")
    let reconstructImage = precompileMetalFunction(functionName: "reconstructSubsampledImage")
    let quantizeImage = precompileMetalFunction(functionName: "quantizeImage")
    let quantizeImageDithering = precompileMetalFunction(functionName: "quantizeImageDither")
}

let metalFunctions = PrecompiledMetalFunctions()

//MARK: Convert to frequency domain DCT
func metal_convertToFrequencyDomainDCTSegm(_ imageDesc: FloatingImageDescription, segmentSize: Int = 8, lut: UnsafePointer<Float>) -> FloatingImageDescription {
    var segSize = segmentSize
    let segmentArea = segmentSize*segmentSize
    let numWidth = imageDesc.width / segmentSize
    let numHeight = imageDesc.height / segmentSize
    var imgWidth = imageDesc.width
    
    var isInverse = false
    var threadwidth = numWidth
    
    // Convert to float, center around zero and copy all image-bytes to `bytes`.
    let bytes = UnsafeMutablePointer<Float>.allocate(capacity: imageDesc.count())
    for i in 0..<imageDesc.count() { bytes[i] = (imageDesc.bytes[i] - 128) }
    
    let resultBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * segmentSize * numWidth*numHeight, options: .storageModeShared)!
    let bytesBuffer: MTLBuffer = device.makeBuffer(bytes: bytes, length: MemoryLayout<Float>.size * imageDesc.count(), options: .storageModeShared)!
    
    performCompiledMetalFunction(metalFunctions.dct2D, numWidth: numWidth, numHeight: numHeight) { commandEncoder in
        
        commandEncoder.setBuffer(bytesBuffer, offset: 0, index: 0)
        
        commandEncoder.setBuffer(resultBuffer, offset: 0, index: 1)
        
        let buffer3 = device.makeBuffer(bytes: lut, length: MemoryLayout<Float>.size * segmentArea, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer3, offset: 0, index: 2)
        
        let buffer4 = device.makeBuffer(bytes: &segSize, length: MemoryLayout<Int>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer4, offset: 0, index: 3)
        
        let buffer5 = device.makeBuffer(bytes: &imgWidth, length: MemoryLayout<Int>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer5, offset: 0, index: 4)
        
        let buffer6 = device.makeBuffer(bytes: &threadwidth, length: MemoryLayout<Int>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer6, offset: 0, index: 5)
        
        let buffer7 = device.makeBuffer(bytes: &isInverse, length: MemoryLayout<Bool>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer7, offset: 0, index: 6)
    }
    
    let valuesPtr = bytesBuffer.contents().assumingMemoryBound(to: Float.self)
    let resultBytes = UnsafeMutablePointer<Float>.allocate(capacity: imageDesc.count())
    copyMemory(dest: resultBytes, source: valuesPtr, count: imageDesc.count())
    bytes.deallocate()
    let imageDescRes = FloatingImageDescription(bytes: resultBytes, width: imageDesc.width, height: imageDesc.height, channels: 1)
    return imageDescRes
}

//MARK: Convert to Image Domain DCT
func metal_convertToImageDomainDCTSegm(_ imageDesc: FloatingImageDescription, segmentSize: Int = 8, lut: UnsafePointer<Float>) -> ImageDescription {
    var segSize = segmentSize
    let segmentArea = segmentSize*segmentSize
    let numWidth = imageDesc.width / segmentSize
    let numHeight = imageDesc.height / segmentSize
    var imgWidth = imageDesc.width
    
    var isInverse = true
    var threadwidth = numWidth
    
    let resultBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * segmentSize * numWidth*numHeight, options: .storageModeShared)!
    let bytesBuffer: MTLBuffer = device.makeBuffer(bytes: imageDesc.bytes, length: MemoryLayout<Float>.size * imageDesc.count(), options: .storageModeShared)!
    
    performCompiledMetalFunction(metalFunctions.dct2DInv, numWidth: numWidth, numHeight: numHeight) { commandEncoder in
        commandEncoder.setBuffer(bytesBuffer, offset: 0, index: 0)
        
        commandEncoder.setBuffer(resultBuffer, offset: 0, index: 1)
        
        let buffer3 = device.makeBuffer(bytes: lut, length: MemoryLayout<Float>.size * segmentArea, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer3, offset: 0, index: 2)
        
        let buffer4 = device.makeBuffer(bytes: &segSize, length: MemoryLayout<Int>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer4, offset: 0, index: 3)
        
        let buffer5 = device.makeBuffer(bytes: &imgWidth, length: MemoryLayout<Int>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer5, offset: 0, index: 4)
        
        let buffer6 = device.makeBuffer(bytes: &threadwidth, length: MemoryLayout<Int>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer6, offset: 0, index: 5)
        
        let buffer7 = device.makeBuffer(bytes: &isInverse, length: MemoryLayout<Bool>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer7, offset: 0, index: 6)
    }
    
    let valuesPtr = bytesBuffer.contents().assumingMemoryBound(to: Float.self)
    let result = UnsafeMutablePointer<UInt8>.allocate(capacity: 1 * imageDesc.count())
    for i in 0..<imageDesc.count() {
        result[i] = UInt8(clamping: Int(abs(valuesPtr[i]+128)))
    }
    return ImageDescription(bytes: result, width: imageDesc.width, height: imageDesc.height, channels: 1)
}

//MARK: Chroma subsample
func metal_chromaSubsample(_ imageDesc: FloatingImageDescription, segmentSize: Int, type: SubsampleType = .first, shouldPixelate:Bool = false) -> FloatingImageDescription {
    
    var function: PrecompiledMetalFunction!
    switch type {
    case.first:     function = metalFunctions.chromaSubsampleFirst
    case.average:   function = metalFunctions.chromaSubsampleAverage
    }
    
    var segSize = segmentSize
    let numKols = imageDesc.width / segmentSize
    let numRows = imageDesc.height / segmentSize
    var imgWidth = imageDesc.width
    let allocsize = imageDesc.channels*imageDesc.count()
    var pixelate = shouldPixelate
    
    let resultBuffer: MTLBuffer! = device.makeBuffer(length: MemoryLayout<Float>.size * allocsize, options: .storageModeShared)!
    
    performCompiledMetalFunction(function, numWidth: numKols, numHeight: numRows) { commandEncoder in
        let buffer1 = device.makeBuffer(bytes: imageDesc.bytes, length: MemoryLayout<Float>.size * allocsize, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer1, offset: 0, index: 0)
        
        commandEncoder.setBuffer(resultBuffer, offset: 0, index: 1)
        
        let buffer2 = device.makeBuffer(bytes: &segSize, length: MemoryLayout<Int>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer2, offset: 0, index: 2)
        
        let buffer3 = device.makeBuffer(bytes: &imgWidth, length: MemoryLayout<Int>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer3, offset: 0, index: 3)
        
        let buffer4 = device.makeBuffer(bytes: &pixelate, length: MemoryLayout<Bool>.size, options: .storageModeShared)!
        commandEncoder.setBuffer(buffer4, offset: 0, index: 4)
    }
    
    let valuesPtr = resultBuffer.contents().assumingMemoryBound(to: Float.self)
    return FloatingImageDescription(bytes: valuesPtr, width: imageDesc.width, height: imageDesc.height, channels: imageDesc.channels)
}

//MARK: Reconstruct with image components
func metal_reconstructWithImageComponents(_ imageDesc: FloatingImageDescription, shouldIncludeAlpha: Bool=true) -> ImageDescription {
    
    if imageDesc.channels != 3 { fatalError("Image description must have 3 channels to extract components") }
    
    var conversion = simd_float3x3(rows: [SIMD3(x: 1, y: 0, z: 1.5748),
                                          SIMD3(x: 1, y: -0.1873, z: -0.4681),
                                          SIMD3(x: 1, y: 1.8556, z: 0)])
    var finalChannels = 3
    if shouldIncludeAlpha { finalChannels = 4 }
    let outputBufferLength = MemoryLayout<UInt8>.size * finalChannels * imageDesc.count()
    
    let outputBuffer = device.makeBuffer(length: outputBufferLength, options: .storageModeShared)
    
    performCompiledMetalFunction(metalFunctions.reconstructImage, numWidth: imageDesc.count(), numHeight: 1) { commandEncoder in
        
        let inputBuffer = device.makeBuffer(bytes: imageDesc.bytes, length: MemoryLayout<Float>.size * 3 * imageDesc.count(), options: .storageModeShared)
        commandEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
        
        commandEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
        
        let conversionBuffer = device.makeBuffer(bytes: &conversion, length: MemoryLayout<simd_float3x3>.size, options: .storageModeShared)
        commandEncoder.setBuffer(conversionBuffer, offset: 0, index: 2)
        
        let finChanBuffer = device.makeBuffer(bytes: &finalChannels, length: MemoryLayout<Int>.size, options: .storageModeShared)
        commandEncoder.setBuffer(finChanBuffer, offset: 0, index: 3)
    }
    
    let output = outputBuffer!.contents().assumingMemoryBound(to: UInt8.self)
    let resultBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: finalChannels*imageDesc.count())
    copyMemory(dest: resultBytes, source: output, count: finalChannels*imageDesc.count())
    return ImageDescription(bytes: resultBytes, width: imageDesc.width, height: imageDesc.height, channels: finalChannels)
}

//MARK: Quantize Image
func metal_quantizeImage(_ imageDesc: FloatingImageDescription, colormap: UnsafePointer<Float>, numColors: Int) {
    if imageDesc.channels != 3 && imageDesc.channels != 4 { fatalError("Image description must have 3 channels to extract components") }
    
    var numColorsP = numColors
    var channels = imageDesc.channels
    let bytesBuffer = device.makeBuffer(bytes: imageDesc.bytes, length: MemoryLayout<Float>.size*channels*imageDesc.count(), options: .storageModeShared)
    
    performCompiledMetalFunction(metalFunctions.quantizeImage, numWidth: imageDesc.count(), numHeight: 1) { commandEncoder in
        
        commandEncoder.setBuffer(bytesBuffer, offset: 0, index: 0)
        
        let colormapBuffer = device.makeBuffer(bytes: colormap, length: MemoryLayout<Float>.size*channels*numColors, options: .storageModeShared)
        commandEncoder.setBuffer(colormapBuffer, offset: 0, index: 1)
        
        let numColorsBuffer = device.makeBuffer(bytes: &numColorsP, length: MemoryLayout<Int>.size, options: .storageModeShared)
        commandEncoder.setBuffer(numColorsBuffer, offset: 0, index: 2)
        
        let channelsBuffer = device.makeBuffer(bytes: &channels, length: MemoryLayout<Int>.size, options: .storageModeShared)
        commandEncoder.setBuffer(channelsBuffer, offset: 0, index: 3)
    }
    
    let output = bytesBuffer!.contents().assumingMemoryBound(to: Float.self)
    copyMemory(dest: imageDesc.bytes, source: output, count: channels*imageDesc.count())
}

//MARK: Quantize Image dithering
func metal_quantizeImageDither(_ imageDesc: FloatingImageDescription, colormap: UnsafePointer<Float>, numColors: Int, dithermap: UnsafePointer<UInt8>, dithermapSize: Int) {
    if imageDesc.channels != 3 && imageDesc.channels != 4 { fatalError("Image description must have 3 channels to extract components") }
    
    let dithermapChannels = 1
    var numColorsP = numColors
    var dithermapSizeP = dithermapSize
    var channels = imageDesc.channels
    var imgSizP = imageDesc.width
    let bytesBuffer = device.makeBuffer(bytes: imageDesc.bytes, length: MemoryLayout<Float>.size*channels*imageDesc.count(), options: .storageModeShared)
    
    performCompiledMetalFunction(metalFunctions.quantizeImageDithering, numWidth: imageDesc.width, numHeight: imageDesc.height) { commandEncoder in
        
        commandEncoder.setBuffer(bytesBuffer, offset: 0, index: 0)
        
        let colormapBuffer = device.makeBuffer(bytes: colormap, length: MemoryLayout<Float>.size*channels*numColors, options: .storageModeShared)
        commandEncoder.setBuffer(colormapBuffer, offset: 0, index: 1)
        
        let dithermapBuffer = device.makeBuffer(bytes: dithermap, length: MemoryLayout<UInt8>.size*dithermapChannels*dithermapSize*dithermapSize, options: .storageModeShared)
        commandEncoder.setBuffer(dithermapBuffer, offset: 0, index: 2)
        
        let dithermapSizeBuffer = device.makeBuffer(bytes: &dithermapSizeP, length: MemoryLayout<Int>.size, options: .storageModeShared)
        commandEncoder.setBuffer(dithermapSizeBuffer, offset: 0, index: 3)
        
        let imageSizeBuffer = device.makeBuffer(bytes: &imgSizP, length: MemoryLayout<Int>.size, options: .storageModeShared)
        commandEncoder.setBuffer(imageSizeBuffer, offset: 0, index: 4)
        
        let numColorsBuffer = device.makeBuffer(bytes: &numColorsP, length: MemoryLayout<Int>.size, options: .storageModeShared)
        commandEncoder.setBuffer(numColorsBuffer, offset: 0, index: 5)
        
        let channelsBuffer = device.makeBuffer(bytes: &channels, length: MemoryLayout<Int>.size, options: .storageModeShared)
        commandEncoder.setBuffer(channelsBuffer, offset: 0, index: 6)
    }
    
    let output = bytesBuffer!.contents().assumingMemoryBound(to: Float.self)
    copyMemory(dest: imageDesc.bytes, source: output, count: channels*imageDesc.count())
}

