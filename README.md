<div align="center">

# 🌍 Cobe for iOS

**A tiny, beautiful, GPU-accelerated WebGL-style globe — rewritten in Swift + Metal.**

Inspired by [`cobe`](https://github.com/shuding/cobe) (the JavaScript original by Shu Ding), reimagined natively for iOS & macOS.

[![Swift 5.5+](https://img.shields.io/badge/Swift-5.5%2B-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2013%2B%20%7C%20macOS%2011%2B-blue.svg?style=flat-square&logo=apple)](https://developer.apple.com)
[![SPM](https://img.shields.io/badge/SPM-Compatible-success.svg?style=flat-square)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Metal](https://img.shields.io/badge/Renderer-Metal-purple.svg?style=flat-square)](https://developer.apple.com/metal/)

</div>

---

## ✨ Features

- 🎨 **Pure Metal** — no CPU drawing, no WebView. Pixel-perfect dot globe shader.
- 🌐 **Faithful port** — same look, same parameters as the original `cobe` JS lib.
- 📍 **Markers + Arcs** — lat/lon pins and great-circle arcs with depth fading.
- 🎯 **Project callback** — get screen coordinates for every marker, every frame. Pin UIKit/SwiftUI overlays on the globe.
- 🌗 **Dark / glow / custom palettes** — full color control (`baseColor`, `markerColor`, `glowColor`, `arcColor`).
- 🎥 **3D perspective** — toggleable depth-based marker scaling.
- 🚀 **60 fps with 500+ markers** — instanced rendering, fragment-shader culling.
- 📦 **Zero dependencies** — single SPM package, ~25 KB of Swift + Metal.

---

## 📸 Demo

The included demo app (`Demo/`) showcases 7 globe styles:

| Style | What |
|---|---|
| **Basic** | Classic white globe, orange markers |
| **Dark** | Black space + cyan markers |
| **Glow** | Neon purple-pink night theme |
| **Emoji** | UIKit emoji anchors that track lat/lon |
| **Arcs** | Great-circle connections between cities |
| **Gallery** | Floating photo cards pinned to coordinates |
| **Card** | Info cards with lat/lon labels |

Interactive: drag to rotate, pinch to zoom, tap to pause, plus a 500-marker stress slider.

```bash
cd Demo
xcodegen          # generates CobeDemo.xcodeproj
open CobeDemo.xcodeproj
```

---

## 📦 Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies…** and paste:

```
https://github.com/bvnkame/cobe-ios
```

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/bvnkame/cobe-ios", from: "1.0.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "Cobe", package: "cobe-ios")
    ])
]
```

---

## 🚀 Quick Start

```swift
import UIKit
import Cobe

final class ViewController: UIViewController {
    private var globe: CobeView!

    override func viewDidLoad() {
        super.viewDidLoad()
        globe = CobeView(frame: view.bounds, device: nil)
        globe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(globe)

        globe.update { o in
            o.scale = 0.9
            o.mapBrightness = 6
            o.baseColor   = .init(1, 1, 1)
            o.markerColor = .init(1, 0.5, 0)
            o.glowColor   = .init(1, 1, 1)
            o.markers = [
                .init(location: .init(37.7595, -122.4367), size: 0.05, id: "sf"),
                .init(location: .init(40.7128,  -74.0060), size: 0.05, id: "ny"),
                .init(location: .init(35.6762, 139.6503), size: 0.05, id: "tyo"),
            ]
        }

        // Auto-spin
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        globe.update { o in o.phi += 0.004 }
    }
}
```

That's the whole API.

---

## 🎨 Options

All options live on `CobeOptions` — modify via `globe.update { o in ... }`:

| Option | Type | Default | Meaning |
|---|---|---|---|
| `phi` | `Float` | `0` | Horizontal rotation (radians) |
| `theta` | `Float` | `0` | Vertical tilt (radians, clamp ±π/2) |
| `scale` | `Float` | `1` | Zoom factor |
| `mapSamples` | `Float` | `10_000` | Number of dots on the map |
| `mapBrightness` | `Float` | `1` | Dot brightness multiplier |
| `mapBaseBrightness` | `Float` | `0` | Ambient floor brightness |
| `baseColor` | `SIMD3<Float>` | `(1,1,1)` | Globe body color |
| `markerColor` | `SIMD3<Float>` | `(1,0.5,0)` | Default marker color |
| `glowColor` | `SIMD3<Float>` | `(1,1,1)` | Atmosphere/glow color |
| `arcColor` | `SIMD3<Float>` | `(0.3,0.6,1)` | Default arc color |
| `arcWidth` | `Float` | `1` | Arc thickness |
| `arcHeight` | `Float` | `0.2` | Arc elevation off the surface |
| `diffuse` | `Float` | `1` | Lighting intensity |
| `dark` | `Float` | `0` | Day/night mix (0 = day, 1 = night) |
| `opacity` | `Float` | `1` | Globe opacity |
| `offset` | `SIMD2<Float>` | `.zero` | Screen-space offset |
| `perspective` | `Float` | `0` | 0 = flat marker scale, 1 = depth-based |
| `markerElevation` | `Float` | `0.05` | Lift markers off the surface |
| `markers` | `[CobeMarker]` | `[]` | Lat/lon pins |
| `arcs` | `[CobeArc]` | `[]` | Great-circle connections |

### Markers

```swift
CobeMarker(
    location: .init(48.8584, 2.2945),   // (lat, lon) in degrees
    size: 0.05,
    color: .init(1, 0.3, 0.8),          // optional, overrides markerColor
    id: "paris"                         // optional, used by onProject
)
```

### Arcs

```swift
CobeArc(
    from: .init(37.7595, -122.4367),
    to:   .init(40.7128, -74.0060),
    color: .init(0.3, 0.8, 1.0),        // optional
    id: "sf-ny"
)
```

---

## 📍 Pinning UIKit/SwiftUI overlays

The renderer exposes an `onProject` callback fired every frame for every marker, with the projected 2D screen position, alpha (for back-of-globe culling), and depth (1 = facing camera, 0 = horizon, <0 = behind):

```swift
globe.cobe.onProject = { [weak self] marker, proj in
    guard let id = marker.id, let v = self?.anchors[id] else { return }
    if proj.alpha <= 0.001 { v.isHidden = true; return }
    v.isHidden = false

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let w = self!.view.bounds.width, h = self!.view.bounds.height
    v.layer.position = CGPoint(x: proj.point.x * w, y: proj.point.y * h)
    v.layer.opacity  = proj.alpha
    let s = CGFloat(0.55 + max(0, proj.depth) * 0.7)
    v.layer.transform = CATransform3DMakeScale(s, s, 1)
    CATransaction.commit()
}
```

Same trick works for arcs via `onProjectArc`.

---

## 🏎 Performance

- **Globe**: full-screen Metal shader, one quad, ~16 000 sampled dots — flat cost.
- **Markers**: instanced drawing. Tested at 500+ markers @ 60 fps on iPhone 12.
- **Arcs**: pre-sampled curve segments, one instance per arc.
- **No CPU per-marker work** — projection happens in the vertex shader; the CPU only reads back screen coords for anchors you care about.

---

## 🛠 Requirements

- iOS 13+ / macOS 11+
- Swift 5.5+
- Metal-capable device (every iPhone since 5s)

---

## 🙏 Credits

- [`cobe`](https://github.com/shuding/cobe) — original JavaScript implementation by [Shu Ding](https://github.com/shuding). MIT.
- Map dot pattern derived from the same equirectangular sample technique.
- This port: shader rewritten for Metal MSL, Swift API mirrors the JS one where it makes sense, with native UIKit/MetalKit lifecycle.

If you ship something with this, [drop a link](https://github.com/bvnkame/cobe-ios/discussions) — would love to see it.

---

## 📄 License

MIT © 2026 — see [LICENSE](LICENSE).

Original cobe © Shu Ding, also MIT.
