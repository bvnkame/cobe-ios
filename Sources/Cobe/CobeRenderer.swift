import Foundation
import Metal
import MetalKit
import simd

// Match Metal struct layout
private struct GlobeUniforms {
    var uResolution: SIMD2<Float>
    var uOffset: SIMD2<Float>
    var uRotation: SIMD2<Float>
    var uDots: Float
    var uScale: Float
    var uBaseColor: SIMD3<Float>; var _p0: Float = 0
    var uGlowColor: SIMD3<Float>; var _p1: Float = 0
    var uRenderParams: SIMD4<Float>
    var uMapBaseBrightness: Float
}

private struct MAUniforms {
    var uPhi: Float
    var uTheta: Float
    var uResolution: SIMD2<Float>
    var uScale: Float
    var uOffset: SIMD2<Float>
    var uMarkerElevation: Float
    var uPerspective: Float
    var _pad: SIMD3<Float> = .zero    // align uColor on 16
    var uColor: SIMD3<Float>
}

private struct MarkerInstance {
    var pos: SIMD3<Float>; var size: Float
    var color: SIMD3<Float>; var hasColor: Float
}

private struct ArcInstance {
    var from: SIMD3<Float>
    var to: SIMD3<Float>
    var height: Float
    var width: Float
    var color: SIMD3<Float>
    var hasColor: Float
}

public final class CobeRenderer: NSObject, MTKViewDelegate {

    public var options = CobeOptions()
    public var onProject: ((CobeMarker, CobeProjection) -> Void)?
    public var onProjectArc: ((CobeArc, CobeProjection) -> Void)?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private var globePipeline: MTLRenderPipelineState!
    private var markerPipeline: MTLRenderPipelineState!
    private var arcPipeline: MTLRenderPipelineState!

    private var quadBuffer: MTLBuffer!
    private var arcSegBuffer: MTLBuffer!
    private var markerInstBuffer: MTLBuffer?
    private var arcInstBuffer: MTLBuffer?
    private var markerCount = 0
    private var arcCount = 0

    private var texture: MTLTexture!
    private var sampler: MTLSamplerState!

    private var pixelFormat: MTLPixelFormat = .bgra8Unorm
    private var size: CGSize = .zero

    public init?(metalDevice: MTLDevice) {
        guard let q = metalDevice.makeCommandQueue() else { return nil }
        self.device = metalDevice
        self.commandQueue = q
        super.init()
    }

    public func configure(view: MTKView) {
        view.device = device
        view.delegate = self
        view.colorPixelFormat = pixelFormat
        view.framebufferOnly = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        #if canImport(UIKit)
        view.isOpaque = false
        view.backgroundColor = .clear
        #endif
        buildPipelines()
        buildBuffers()
        loadTexture()
        size = view.drawableSize
    }

    private func buildPipelines() {
        let library: MTLLibrary
        do {
            #if SWIFT_PACKAGE
            library = try device.makeDefaultLibrary(bundle: .module)
            #else
            library = device.makeDefaultLibrary()!
            #endif
        } catch {
            fatalError("Cobe: failed to load Metal library: \(error)")
        }

        func make(_ vert: String, _ frag: String) -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: vert)
            desc.fragmentFunction = library.makeFunction(name: frag)
            desc.colorAttachments[0].pixelFormat = pixelFormat
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].rgbBlendOperation = .add
            desc.colorAttachments[0].alphaBlendOperation = .add
            desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try! device.makeRenderPipelineState(descriptor: desc)
        }

        globePipeline = make("globe_vertex", "globe_fragment")
        markerPipeline = make("marker_vertex", "marker_fragment")
        arcPipeline = make("arc_vertex", "arc_fragment")
    }

    private func buildBuffers() {
        var quad: [SIMD2<Float>] = [
            SIMD2(-1,-1), SIMD2(1,-1), SIMD2(-1,1),
            SIMD2(-1, 1), SIMD2(1,-1), SIMD2(1, 1),
        ]
        quadBuffer = device.makeBuffer(bytes: &quad,
                                       length: quad.count * MemoryLayout<SIMD2<Float>>.stride,
                                       options: [])

        var seg: [SIMD2<Float>] = []
        for i in 0...32 {
            let t = Float(i) / 32.0
            seg.append(SIMD2(t, -1))
            seg.append(SIMD2(t,  1))
        }
        arcSegBuffer = device.makeBuffer(bytes: &seg,
                                         length: seg.count * MemoryLayout<SIMD2<Float>>.stride,
                                         options: [])
    }

    private func loadTexture() {
        let loader = MTKTextureLoader(device: device)
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = .module
        #else
        bundle = Bundle(for: CobeRenderer.self)
        #endif
        if let url = bundle.url(forResource: "texture", withExtension: "png"),
           let tex = try? loader.newTexture(URL: url, options: [.SRGB: false]) {
            self.texture = tex
        } else {
            // 1×1 fallback
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 1, height: 1, mipmapped: false)
            self.texture = device.makeTexture(descriptor: desc)
            var px: UInt8 = 0
            self.texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 1)
        }
        let s = MTLSamplerDescriptor()
        s.minFilter = .nearest; s.magFilter = .nearest
        s.sAddressMode = .repeat; s.tAddressMode = .repeat
        sampler = device.makeSamplerState(descriptor: s)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange newSize: CGSize) {
        size = newSize
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rp = view.currentRenderPassDescriptor,
              let cb = commandQueue.makeCommandBuffer() else { return }

        rebuildInstances()
        publishAnchors()

        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }

        // Globe
        var gu = GlobeUniforms(
            uResolution: SIMD2(Float(size.width), Float(size.height)),
            uOffset: options.offset * UIScreenScale(),
            uRotation: SIMD2(options.phi, options.theta),
            uDots: options.mapSamples,
            uScale: options.scale,
            uBaseColor: options.baseColor,
            uGlowColor: options.glowColor,
            uRenderParams: SIMD4(options.mapBrightness, options.diffuse, options.dark, options.opacity),
            uMapBaseBrightness: options.mapBaseBrightness
        )
        enc.setRenderPipelineState(globePipeline)
        enc.setVertexBuffer(quadBuffer, offset: 0, index: 0)
        enc.setFragmentBytes(&gu, length: MemoryLayout<GlobeUniforms>.stride, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        // Arcs
        if let arcBuf = arcInstBuffer, arcCount > 0 {
            var u = MAUniforms(uPhi: options.phi, uTheta: options.theta,
                               uResolution: SIMD2(Float(size.width), Float(size.height)),
                               uScale: options.scale,
                               uOffset: options.offset * UIScreenScale(),
                               uMarkerElevation: options.markerElevation,
                               uPerspective: 0,
                               _pad: .zero,
                               uColor: options.arcColor)
            enc.setRenderPipelineState(arcPipeline)
            enc.setVertexBuffer(arcSegBuffer, offset: 0, index: 0)
            enc.setVertexBuffer(arcBuf, offset: 0, index: 1)
            enc.setVertexBytes(&u, length: MemoryLayout<MAUniforms>.stride, index: 2)
            enc.setFragmentBytes(&u, length: MemoryLayout<MAUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 66, instanceCount: arcCount)
        }

        // Markers
        if let markerBuf = markerInstBuffer, markerCount > 0 {
            var u = MAUniforms(uPhi: options.phi, uTheta: options.theta,
                               uResolution: SIMD2(Float(size.width), Float(size.height)),
                               uScale: options.scale,
                               uOffset: options.offset * UIScreenScale(),
                               uMarkerElevation: options.markerElevation,
                               uPerspective: options.perspective,
                               _pad: .zero,
                               uColor: options.markerColor)
            enc.setRenderPipelineState(markerPipeline)
            enc.setVertexBuffer(quadBuffer, offset: 0, index: 0)
            enc.setVertexBuffer(markerBuf, offset: 0, index: 1)
            enc.setVertexBytes(&u, length: MemoryLayout<MAUniforms>.stride, index: 2)
            enc.setFragmentBytes(&u, length: MemoryLayout<MAUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: markerCount)
        }

        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    private func UIScreenScale() -> Float {
        #if canImport(UIKit)
        return Float(UIScreen.main.scale)
        #else
        return 1.0
        #endif
    }

    // MARK: - Instances

    private func rebuildInstances() {
        // Markers
        markerCount = options.markers.count
        if markerCount > 0 {
            var arr = [MarkerInstance]()
            arr.reserveCapacity(markerCount)
            for m in options.markers {
                let p = latLonTo3D(m.location)
                arr.append(MarkerInstance(pos: p, size: m.size,
                                          color: m.color ?? .zero,
                                          hasColor: m.color != nil ? 1 : 0))
            }
            markerInstBuffer = device.makeBuffer(bytes: arr, length: arr.count * MemoryLayout<MarkerInstance>.stride, options: [])
        } else {
            markerInstBuffer = nil
        }

        // Arcs
        arcCount = options.arcs.count
        if arcCount > 0 {
            var arr = [ArcInstance]()
            arr.reserveCapacity(arcCount)
            for a in options.arcs {
                arr.append(ArcInstance(
                    from: latLonTo3D(a.from),
                    to:   latLonTo3D(a.to),
                    height: options.arcHeight + options.markerElevation,
                    width:  options.arcWidth * 0.005,
                    color:  a.color ?? .zero,
                    hasColor: a.color != nil ? 1 : 0
                ))
            }
            arcInstBuffer = device.makeBuffer(bytes: arr, length: arr.count * MemoryLayout<ArcInstance>.stride, options: [])
        } else {
            arcInstBuffer = nil
        }
    }

    private func publishAnchors() {
        guard onProject != nil || onProjectArc != nil else { return }
        for m in options.markers {
            onProject?(m, project(loc: m.location))
        }
        for a in options.arcs {
            onProjectArc?(a, projectArcMid(a))
        }
    }

    // MARK: - Projection

    private func latLonTo3D(_ loc: SIMD2<Double>) -> SIMD3<Float> {
        let lat: Double = loc.x * .pi / 180.0
        let lon: Double = loc.y * .pi / 180.0 - .pi
        let cl: Double = cos(lat)
        let x: Double = -cl * cos(lon)
        let y: Double = sin(lat)
        let z: Double = cl * sin(lon)
        return SIMD3(Float(x), Float(y), Float(z))
    }

    private func applyRotation(_ p: SIMD3<Float>) -> CobeProjection {
        let cx: Float = cos(options.theta)
        let cy: Float = cos(options.phi)
        let sx: Float = sin(options.theta)
        let sy: Float = sin(options.phi)
        let aspect: Float = Float(size.width) / Float(size.height)

        let px: Float = p.x, py: Float = p.y, pz: Float = p.z
        let rx: Float = cy * px + sy * pz
        let ryA: Float = sy * sx * px
        let ryB: Float = cx * py
        let ryC: Float = cy * sx * pz
        let ry: Float = ryA + ryB - ryC
        let rzA: Float = -sy * cx * px
        let rzB: Float = sx * py
        let rzC: Float = cy * cx * pz
        let rz: Float = rzA + rzB + rzC

        let dpr: Float = UIScreenScale()
        let w: Float = Float(size.width)
        let h: Float = Float(size.height)
        let scale: Float = options.scale
        let ox: Float = options.offset.x
        let oy: Float = options.offset.y

        let xN: Float = (rx / aspect) * scale + ox * scale * dpr / w
        let yN: Float = -ry * scale + oy * scale * dpr / h
        let xS: Float = (xN + 1.0) * 0.5
        let yS: Float = (yN + 1.0) * 0.5

        // Alpha: fade across silhouette; occluded behind globe → 0
        let radial: Float = rx * rx + ry * ry
        let inSilhouette: Bool = radial < 0.64
        let alpha: Float
        if rz < 0 && inSilhouette {
            alpha = 0
        } else {
            let t: Float = max(0, min(1, (rz + 0.15) / 0.30))
            alpha = t * t * (3 - 2 * t)
        }
        return CobeProjection(point: CGPoint(x: CGFloat(xS), y: CGFloat(yS)),
                              alpha: alpha,
                              depth: rz)
    }

    private func project(loc: SIMD2<Double>) -> CobeProjection {
        let p = latLonTo3D(loc)
        let r: Float = 0.8 + options.markerElevation
        return applyRotation(p * r)
    }

    private func projectArcMid(_ a: CobeArc) -> CobeProjection {
        let from = latLonTo3D(a.from)
        let to = latLonTo3D(a.to)
        let m = from + to
        let len = simd_length(m)
        if len < 0.001 { return CobeProjection(point: .zero, alpha: 0, depth: -1) }
        let endpointR: Float = 0.8 + options.markerElevation
        let arcR: Float = 0.8 + options.arcHeight + options.markerElevation
        let s: Float = 0.25 * endpointR + (0.5 * arcR) / len
        return applyRotation(m * s)
    }
}

#if canImport(UIKit)
import UIKit
#endif
