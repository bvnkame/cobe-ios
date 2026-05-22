#if canImport(UIKit)
import UIKit
import MetalKit

public final class CobeView: MTKView {

    public let cobe: CobeRenderer

    public override init(frame frameRect: CGRect, device: MTLDevice?) {
        let dev = device ?? MTLCreateSystemDefaultDevice()!
        self.cobe = CobeRenderer(metalDevice: dev)!
        super.init(frame: frameRect, device: dev)
        cobe.configure(view: self)
    }

    public required init(coder: NSCoder) {
        let dev = MTLCreateSystemDefaultDevice()!
        self.cobe = CobeRenderer(metalDevice: dev)!
        super.init(coder: coder)
        self.device = dev
        cobe.configure(view: self)
    }

    public func update(_ block: (inout CobeOptions) -> Void) {
        block(&cobe.options)
        setNeedsDisplay()
    }
}
#elseif canImport(AppKit)
import AppKit
import MetalKit

public final class CobeView: MTKView {

    public let cobe: CobeRenderer

    public override init(frame frameRect: CGRect, device: MTLDevice?) {
        let dev = device ?? MTLCreateSystemDefaultDevice()!
        self.cobe = CobeRenderer(metalDevice: dev)!
        super.init(frame: frameRect, device: dev)
        wantsLayer = true
        layer?.isOpaque = false
        cobe.configure(view: self)
    }

    public required init(coder: NSCoder) {
        let dev = MTLCreateSystemDefaultDevice()!
        self.cobe = CobeRenderer(metalDevice: dev)!
        super.init(coder: coder)
        self.device = dev
        wantsLayer = true
        layer?.isOpaque = false
        cobe.configure(view: self)
    }

    public func update(_ block: (inout CobeOptions) -> Void) {
        block(&cobe.options)
        needsDisplay = true
    }
}
#endif
