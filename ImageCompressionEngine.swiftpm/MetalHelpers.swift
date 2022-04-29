//
//  File.swift
//  ImageCompressionEngine
//
//  Created by Eskil Sviggum on 02/04/2022.
//

import Foundation
import Metal

let device: MTLDevice = MTLCreateSystemDefaultDevice()!

struct PrecompiledMetalFunction {
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState
    let mx: Int
}

func makeLibrary(fromResourceWithName name: String) -> MTLLibrary? {
    do {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8)
        else { return nil }
        
        let library = try device.makeLibrary(source: source, options: nil)
        
        return library
    } catch {
        print(error)
        return nil
    }
}

func precompileMetalFunction(functionName: String) -> PrecompiledMetalFunction {
    let library: MTLLibrary = makeLibrary(fromResourceWithName: "MetalFunctions")!
    let kernelFunction: MTLFunction = (library.makeFunction(name: functionName))!
    
    var pipelineState: MTLComputePipelineState!
    do {
        pipelineState = try device.makeComputePipelineState(function: kernelFunction)
    }
    catch {
        print(error)
        fatalError("Could not make pipeline")
    }
    
    let commandQueue: MTLCommandQueue = device.makeCommandQueue()!
    
    let max = device.maxThreadsPerThreadgroup
    let mx = Int(sqrt(Double(max.width)))
    
    return PrecompiledMetalFunction(commandQueue: commandQueue, pipelineState: pipelineState, mx: mx)
}

func performCompiledMetalFunction(_ function: PrecompiledMetalFunction, numWidth: Int, numHeight: Int, commandEncoderConfiguration: (MTLComputeCommandEncoder)->Void) {
    let commandBuffer: MTLCommandBuffer = function.commandQueue.makeCommandBuffer()!
    let commandEncoder:  MTLComputeCommandEncoder = commandBuffer.makeComputeCommandEncoder()!
    commandEncoder.setComputePipelineState(function.pipelineState)
    
    commandEncoderConfiguration(commandEncoder)
    
    let threadGroupCount = MTLSizeMake(min(function.mx, numWidth), min(function.mx, numHeight), 1)
    let threadGroups: MTLSize = MTLSizeMake(((numWidth-1) / threadGroupCount.width) + 1, ((numHeight-1) / threadGroupCount.height) + 1, 1)
    commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
    commandEncoder.endEncoding()
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
}
