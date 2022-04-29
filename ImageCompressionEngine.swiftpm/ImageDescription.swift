//
//  ImageDescription.swift
//  ImageCompressionEngine
//
//  Created by Eskil Sviggum on 02/04/2022.
//

import Foundation

struct GenericImageDescription<T:Numeric> {
    var bytes: UnsafeMutablePointer<T>
    let width: Int
    let height: Int
    let channels: Int
    
    func count() -> Int {
        return width * height
    }
    
    func createCopy() -> Self {
        let cnt = channels*width*height
        let bytes = UnsafeMutablePointer<T>.allocate(capacity: cnt)
        copyMemory(dest: bytes, source: self.bytes, count: cnt)
        return .init(bytes: bytes, width: width, height: height, channels: channels)
    }
    
    func release() {
        bytes.deallocate()
    }
}

typealias ImageDescription = GenericImageDescription<UInt8>
typealias FloatingImageDescription = GenericImageDescription<Float>
