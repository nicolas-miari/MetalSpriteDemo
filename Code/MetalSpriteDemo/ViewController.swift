//
//  ViewController.swift
//  MetalSpriteDemo
//
//  Created by Nicolás Miari on 2019/04/10.
//  Copyright © 2019 Nicolás Miari. All rights reserved.
//

import Cocoa
import Metal
import MetalKit

class ViewController: NSViewController {

    private var renderer: Renderer!
    private var textureLoader: MTKTextureLoader!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = MTLCreateSystemDefaultDevice() else {
            NSAlert(error: NSError(localizedDescription: "Failed to create Metal device!")).runModal()
            return
        }

        let metalView = MTKView(frame: view.bounds, device: device)

        view.addSubview(metalView)

        do {
            let renderer = try Renderer(view: metalView)
            self.renderer = renderer
        } catch {
            NSAlert(error: error).runModal()
            return
        }

        self.textureLoader = MTKTextureLoader(device: device)

        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            .SRGB: NSNumber(value: true) // TEST...
        ]
        textureLoader.newTexture(name: "Texture", scaleFactor: 1, bundle: nil, options: options) { [unowned self](texture, error) in
            guard let texture = texture else {
                return
            }
            // Pass the created texture and render:
            self.renderer.texture = texture
            self.renderer.render()
        }
    }
}

