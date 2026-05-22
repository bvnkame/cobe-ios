import Foundation
import simd

public struct CobeMarker {
    public var location: SIMD2<Double>   // (lat, lon) degrees
    public var size: Float
    public var color: SIMD3<Float>?
    public var id: String?
    public init(location: SIMD2<Double>, size: Float, color: SIMD3<Float>? = nil, id: String? = nil) {
        self.location = location; self.size = size; self.color = color; self.id = id
    }
}

public struct CobeArc {
    public var from: SIMD2<Double>
    public var to: SIMD2<Double>
    public var color: SIMD3<Float>?
    public var id: String?
    public init(from: SIMD2<Double>, to: SIMD2<Double>, color: SIMD3<Float>? = nil, id: String? = nil) {
        self.from = from; self.to = to; self.color = color; self.id = id
    }
}

public struct CobeProjection {
    public let point: CGPoint
    public let alpha: Float
    public let depth: Float   // 1.0 = facing camera, 0 = horizon edge, < 0 = behind globe
}

public struct CobeOptions {
    public var phi: Float = 0
    public var theta: Float = 0
    public var perspective: Float = 0   // 0 = flat marker scale, 1 = full depth scale
    public var mapSamples: Float = 10_000
    public var mapBrightness: Float = 1
    public var mapBaseBrightness: Float = 0
    public var baseColor: SIMD3<Float> = .init(1, 1, 1)
    public var markerColor: SIMD3<Float> = .init(1, 0.5, 0)
    public var glowColor: SIMD3<Float> = .init(1, 1, 1)
    public var arcColor: SIMD3<Float> = .init(0.3, 0.6, 1)
    public var arcWidth: Float = 1
    public var arcHeight: Float = 0.2
    public var diffuse: Float = 1
    public var dark: Float = 0
    public var opacity: Float = 1
    public var offset: SIMD2<Float> = .zero
    public var scale: Float = 1
    public var markerElevation: Float = 0.05
    public var markers: [CobeMarker] = []
    public var arcs: [CobeArc] = []
    public init() {}
}
