//
//  Renderer.swift
//  MetalSpriteDemo
//
//  Created by Nicolás Miari on 2019/04/10.
//  Copyright © 2019 Nicolás Miari. All rights reserved.
//

import Metal
import MetalKit
import simd

fileprivate let maximumInflightBuffers: Int = 3

struct Constants {
    var modelViewProjectionMatrix = float4x4()
}

struct Vertex {
    var position = float4(x: 0, y: 0, z: 0, w: 1)
    var textureCoordinate = float2(x: 0, y: 0)
}

// MARK: -

class Renderer: NSObject {

    public var texture: MTLTexture!

    private let targetView: MTKView
    private let commandQueue: MTLCommandQueue
    private let renderPipeline: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState
    private let resolveRenderPassDescriptor: MTLRenderPassDescriptor
    private let sampler: MTLSamplerState
    private var constants = Constants()
    private var projectionMatrix: float4x4
    private let indexBuffer: MTLBuffer
    private let vertexBuffer: MTLBuffer

    init(view: MTKView) throws {
        guard let device = view.device else {
            throw NSError(localizedDescription: "Failed to acquire Metal device.")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw NSError(localizedDescription: "Failed to create Metal command queue.")
        }

        self.commandQueue = commandQueue
        self.targetView = view

        // Gets view's drawable attached before rendering the resolve pass each frame
        self.resolveRenderPassDescriptor = MTLRenderPassDescriptor()
        self.renderPipeline = try createRenderPipelineState(for: targetView)
        self.depthStencilState = try createDepthStencilState(from: device)
        self.sampler = try createSamplerState(from: device)

        resolveRenderPassDescriptor.depthAttachment.texture = try createDepthAttachmentTexture(for: view)

        let width = Float( targetView.bounds.width)
        let height = Float(targetView.bounds.height)

        let projectionDescriptor = OrthographicProjectionDescriptor(
            left: -1*width,
            right: +1*width,
            bottom: -1*height,
            top: +1*height,
            near: 0,
            far: 2
        )
        self.projectionMatrix = orthographicProjectionMatrix(projectionDescriptor)

        constants.modelViewProjectionMatrix = projectionMatrix

        self.vertexBuffer = try createVertexBuffer(using: device)
        self.indexBuffer = try createIndexBuffer(using: device)
    }

    func render() {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        defer {
            commandBuffer.commit() // (executed on any return past this point)
        }
        commandBuffer.enqueue()
        guard let drawable = targetView.currentDrawable, targetView.currentRenderPassDescriptor != nil else {
            return
        }

        let metalColor = MTLClearColor(red: 1, green:0, blue: 0, alpha: 1)

        resolveRenderPassDescriptor.colorAttachments[0].texture = drawable.texture
        resolveRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        resolveRenderPassDescriptor.colorAttachments[0].storeAction = .store
        resolveRenderPassDescriptor.colorAttachments[0].clearColor = metalColor

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: resolveRenderPassDescriptor) else {
            return
        }

        // Render Textured Quad...

        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(.none)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setRenderPipelineState(renderPipeline)
        renderEncoder.setFragmentSamplerState(sampler, index: 0)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(texture, index: 0)

        // Pass uniforms to VERTEX shader:
        renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)

        // Pass uniforms to FRAGMENT shader:
        renderEncoder.setFragmentBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)

        renderEncoder.drawIndexedPrimitives(
            type: MTLPrimitiveType.triangleStrip,
            indexCount: 6,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0)

        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
    }
}

// MARK: - Metal Resource Creation Support

fileprivate func createDepthAttachmentTexture(for view: MTKView) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .depth32Float,
        width: Int(view.drawableSize.width),
        height: Int(view.drawableSize.height),
        mipmapped: false)
    descriptor.usage = .renderTarget
    descriptor.storageMode = .private
    descriptor.sampleCount = view.sampleCount

    guard let depthTexture = view.device?.makeTexture(descriptor: descriptor) else {
        throw NSError(localizedDescription: "Failed to create depth texture.")
    }
    return depthTexture
}

fileprivate func createColorAttachmentTexture(for view: MTKView) throws -> MTLTexture {
    let textureDescriptor = MTLTextureDescriptor()
    textureDescriptor.pixelFormat = view.colorPixelFormat
    textureDescriptor.sampleCount = 1
    textureDescriptor.width = Int(view.drawableSize.width)
    textureDescriptor.height = Int(view.drawableSize.height)
    textureDescriptor.depth = 1
    textureDescriptor.textureType = MTLTextureType.type2D
    textureDescriptor.usage = [.renderTarget, .shaderRead]
    textureDescriptor.resourceOptions = .storageModePrivate // ???

    guard let colorTexture = view.device?.makeTexture(descriptor: textureDescriptor) else {
        throw NSError()
    }
    return colorTexture
}

fileprivate func createDepthStencilState(from device: MTLDevice) throws -> MTLDepthStencilState {
    let descriptor = MTLDepthStencilDescriptor()

    // No depth test (we are rendering translucents):
    descriptor.isDepthWriteEnabled = false
    descriptor.depthCompareFunction = .always

    guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
        throw NSError(localizedDescription: "Failed to create depth^stencil state.")
    }
    return state
}

/**
 - todo: Create a separate pipeline for rendering fully opaque objects?
 */
fileprivate func createRenderPipelineState(for view: MTKView) throws -> MTLRenderPipelineState {
    guard let device = view.device else {
        throw NSError(localizedDescription: "Failed to acquire Metal device.")
    }
    let bundle = Bundle(for: Renderer.self)
    let library = try device.makeDefaultLibrary(bundle: bundle)

    let vertexFunction = library.makeFunction(name: "sprite_vertex_transform")
    let fragmentFunction = library.makeFunction(name: "sprite_fragment_textured")

    let descriptor = MTLRenderPipelineDescriptor()

    descriptor.sampleCount = view.sampleCount
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction
    descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
    descriptor.depthAttachmentPixelFormat = .depth32Float

    descriptor.colorAttachments[0].isBlendingEnabled = true

    /*
     BLENDING PARAMETERS
     */
    descriptor.colorAttachments[0].rgbBlendOperation = .add
    descriptor.colorAttachments[0].alphaBlendOperation = .add

    descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha

    descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

    return try device.makeRenderPipelineState(descriptor: descriptor)
}

fileprivate func createSamplerState(from device: MTLDevice) throws -> MTLSamplerState {
    let descriptor = MTLSamplerDescriptor()
    descriptor.sAddressMode = .clampToEdge
    descriptor.tAddressMode = .clampToEdge
    descriptor.normalizedCoordinates = true
    descriptor.minFilter = .nearest
    descriptor.magFilter = .nearest

    guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
        throw NSError()
    }
    return sampler
}

fileprivate func createVertexBuffer(using device: MTLDevice) throws -> MTLBuffer {

    let halfSize: Float = 100

    var v0 = Vertex()
    v0.position.x = -halfSize
    v0.position.y = +halfSize
    v0.textureCoordinate.x = 0
    v0.textureCoordinate.y = 1

    var v1 = Vertex()
    v1.position.x = -halfSize
    v1.position.y = -halfSize
    v1.textureCoordinate.x = 0
    v1.textureCoordinate.y = 0

    var v2 = Vertex()
    v2.position.x = +halfSize
    v2.position.y = +halfSize
    v2.textureCoordinate.x = 1
    v2.textureCoordinate.y = 1

    var v3 = Vertex()
    v3.position.x = +halfSize
    v3.position.y = -halfSize
    v3.textureCoordinate.x = 1
    v3.textureCoordinate.y = 0

    let vertices = [v0, v1, v2, v3]
    let vertexBufferSize = vertices.count * MemoryLayout<Vertex>.stride

    guard let buffer = device.makeBuffer(bytes: vertices, length: vertexBufferSize, options: []) else {
        throw NSError(localizedDescription: "Failed to Create Metal Vertex Buffer.")
    }
    return buffer
}

// Indices for drawing a quad as triangles
fileprivate func createIndexBuffer(using device: MTLDevice) throws -> MTLBuffer {

    let indices: [UInt32] = [
        // First trianlge:
        0, 1, 2,

        // Seconnd triangle:
        2, 1, 3
    ]

    let indexBufferSize = indices.count * MemoryLayout<UInt32>.stride

    guard let buffer = device.makeBuffer(bytes: indices, length: indexBufferSize, options: []) else {
        throw NSError(localizedDescription: "Failed to Create Metal Index Buffer.")
    }
    return buffer
}
