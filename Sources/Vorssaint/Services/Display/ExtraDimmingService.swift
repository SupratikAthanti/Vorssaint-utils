// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Metal
import QuartzCore

/// Implements extra dimming below normal minimum by using a fullscreen
/// overlay window with a "multiply" compositing filter.
final class ExtraDimmingService: ObservableObject {
    static let shared = ExtraDimmingService()
    
    @Published private(set) var enabled = false
    
    private var overlayWindow: NSWindow?
    private var overlayLayer: CAMetalLayer?
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    
    private init() {}
    
    func setDimmingLevel(_ level: Double) {
        // level: 0.0 (fully black) to 1.0 (no dimming)
        if level >= 1.0 {
            stop()
        } else {
            start(factor: level)
        }
    }
    
    private func start(factor: Double) {
        enabled = true
        guard let screen = NSScreen.main else { return }
        
        if overlayWindow == nil {
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.sharingType = .none
            window.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
            
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue() else { return }
            
            let layer = CAMetalLayer()
            layer.device = device
            layer.pixelFormat = .rgba16Float
            layer.compositingFilter = "multiply"
            layer.frame = CGRect(origin: .zero, size: screen.frame.size)
            
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer = layer
            window.contentView = view
            
            overlayWindow = window
            overlayLayer = layer
            metalDevice = device
            commandQueue = queue
            window.orderFrontRegardless()
        }
        
        render(factor: factor)
    }
    
    func stop() {
        enabled = false
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayLayer = nil
    }
    
    private func render(factor: Double) {
        guard let layer = overlayLayer,
              let queue = commandQueue,
              let drawable = layer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { return }
        
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: factor, green: factor,
                                                            blue: factor, alpha: 1.0)
        
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }
}
