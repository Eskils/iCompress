//
//  DCT.swift
//  DCT2DCompress
//
//  Created by Eskil Sviggum on 12/02/2022.
//

import Foundation

func dctscale(_ k: Int) -> Float {
    if k == 0 { return 1/sqrt(2) }
    else { return 1 }
}

func createDiscreteCosineLUT(count N: Int) -> UnsafePointer<Float> {
    let bytes = UnsafeMutablePointer<Float>.allocate(capacity: (N)*(N))
    for k in 0..<N {
        for n in 0..<N {
            let value = cos(Float.pi * Float(k)/Float(N) * (Float(n)+0.5))
            bytes[k*(N) + n] = value
        }
    }
    return UnsafePointer(bytes)
}

func dct(inp: UnsafePointer<Float>, out: UnsafeMutablePointer<Float>, lut: UnsafePointer<Float>, size N: Int, offset: Int = 0, inStride: Int = 1, outStride: Int = 1) {
    let scale = sqrt(2 / Float(N))
    for k in 0..<N {
        let outIdx = k*outStride
        out[outIdx] = 0
        for n in 0..<N {
            out[outIdx] += inp[offset + n*inStride] * lut[k*N + n];
        }
        out[outIdx] *= scale * dctscale(k)
    }
}

func idct(inp: UnsafePointer<Float>, out: UnsafeMutablePointer<Float>, lut: UnsafePointer<Float>, size N: Int, offset: Int = 0, inStride: Int = 1, outStride: Int = 1) {
    let scale = sqrt(2 / Float(N))
    for k in 0..<N {
        let outIdx = k*outStride
        out[outIdx] = 0
        for n in 0..<N {
            out[outIdx] += scale * dctscale(n) * inp[offset + n*inStride] * lut[n*N + k];
        }
    }
}


func dct2D(_ values: UnsafeMutablePointer<Float>, lut: UnsafePointer<Float>, width: Int, height: Int, x: Int, y:Int, segmSize: Int, numSegments: Int) {
    let resultBuffer = UnsafeMutablePointer<Float>.allocate(capacity: segmSize)
    let offset = segmSize * (y*width + x)
    
    //First perform on each row
    for row in 0..<segmSize {
        let rowOff = (row) * width
        dct(inp: values, out: resultBuffer, lut: lut, size: segmSize, offset: offset + rowOff, inStride: 1, outStride: 1)
        copyMemory(dest: values, source: resultBuffer, count: segmSize, dstOffset: offset + rowOff)
    }
    
    //Then perform on each column
    for col in 0..<segmSize {
        dct(inp: values, out: resultBuffer, lut: lut, size: segmSize, offset: offset + col, inStride: width, outStride: 1)
        copyMemory(dest: values, source: resultBuffer, count: segmSize, dstOffset: offset + col, dstStride: width)
    }
    
    resultBuffer.deallocate()
}

func dct2DInv(_ values: UnsafeMutablePointer<Float>, lut: UnsafePointer<Float>, width: Int, height: Int, x: Int, y:Int, segmSize: Int) {
    let resultBuffer = UnsafeMutablePointer<Float>.allocate(capacity: segmSize)
    let offset = segmSize * (y*width + x)
    
    //First perform on each row
    for row in 0..<segmSize {
        let rowOff = (row) * width
        idct(inp: values, out: resultBuffer, lut: lut, size: segmSize, offset: offset + rowOff, inStride: 1, outStride: 1)
        copyMemory(dest: values.advanced(by: offset + rowOff), source: resultBuffer, count: segmSize)
    }
    
    //Then perform on each column
    for col in 0..<segmSize {
        idct(inp: values, out: resultBuffer, lut: lut, size: segmSize, offset: offset + col, inStride: width, outStride: 1)
        copyMemory(dest: values.advanced(by: offset + col), source: resultBuffer, count: segmSize, dstStride: width)
    }
    
    resultBuffer.deallocate()
}
