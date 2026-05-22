import AppKit
import Cobe
import simd

enum MacDemoKind: Int, CaseIterable {
    case basic, dark, glow, arcs
    var title: String {
        switch self {
        case .basic: return "Basic"
        case .dark:  return "Dark"
        case .glow:  return "Glow"
        case .arcs:  return "Arcs"
        }
    }
}

final class ViewController: NSViewController {

    private var globe: CobeView!
    private var displayLink: CVDisplayLink?

    private var phi: Float = -1.4
    private var theta: Float = 0.25
    private var autoSpin: Bool = true
    private var demo: MacDemoKind = .arcs

    private var userScale: Float = 0.55
    private var brightness: Float = 6
    private var markerSize: Float = 0.05

    private var scaleSlider: NSSlider!
    private var brightnessSlider: NSSlider!
    private var markerSlider: NSSlider!
    private var spinSwitch: NSSwitch!
    private var demoPopup: NSPopUpButton!
    private var fpsLabel: NSTextField!

    private var lastTick: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var frameAccum: CFTimeInterval = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildGlobe()
        buildInspector()
        applyDemo()
        startTicker()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopTicker()
    }

    private func buildGlobe() {
        globe = CobeView(frame: .zero, device: nil)
        globe.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(globe)
        NSLayoutConstraint.activate([
            globe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            globe.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -260),
            globe.topAnchor.constraint(equalTo: view.topAnchor),
            globe.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let pan = NSPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        globe.addGestureRecognizer(pan)
    }

    private func buildInspector() {
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.widthAnchor.constraint(equalToConstant: 260),
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            stack.topAnchor.constraint(equalTo: panel.topAnchor),
        ])

        let title = NSTextField(labelWithString: "Cobe")
        title.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(title)

        fpsLabel = NSTextField(labelWithString: "—")
        fpsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        fpsLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(fpsLabel)

        demoPopup = NSPopUpButton()
        for kind in MacDemoKind.allCases {
            demoPopup.addItem(withTitle: kind.title)
        }
        demoPopup.selectItem(at: demo.rawValue)
        demoPopup.target = self
        demoPopup.action = #selector(onDemoChanged(_:))
        stack.addArrangedSubview(labeled("Style", demoPopup))

        scaleSlider = makeSlider(min: 0.3, max: 1.5, value: Double(userScale), action: #selector(onScale(_:)))
        stack.addArrangedSubview(labeled("Scale", scaleSlider))

        brightnessSlider = makeSlider(min: 1, max: 12, value: Double(brightness), action: #selector(onBrightness(_:)))
        stack.addArrangedSubview(labeled("Brightness", brightnessSlider))

        markerSlider = makeSlider(min: 0.01, max: 0.12, value: Double(markerSize), action: #selector(onMarkerSize(_:)))
        stack.addArrangedSubview(labeled("Marker size", markerSlider))

        spinSwitch = NSSwitch()
        spinSwitch.state = autoSpin ? .on : .off
        spinSwitch.target = self
        spinSwitch.action = #selector(onSpinToggle(_:))
        stack.addArrangedSubview(labeled("Auto spin", spinSwitch))

        let credit = NSTextField(wrappingLabelWithString: "Drag the globe to rotate.\nMetal renderer + ad-hoc signed DMG.")
        credit.font = .systemFont(ofSize: 11)
        credit.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(credit)
    }

    private func labeled(_ text: String, _ ctrl: NSView) -> NSView {
        let wrap = NSStackView()
        wrap.orientation = .vertical
        wrap.alignment = .leading
        wrap.spacing = 4
        let lbl = NSTextField(labelWithString: text)
        lbl.font = .systemFont(ofSize: 11, weight: .medium)
        lbl.textColor = .secondaryLabelColor
        wrap.addArrangedSubview(lbl)
        wrap.addArrangedSubview(ctrl)
        ctrl.translatesAutoresizingMaskIntoConstraints = false
        ctrl.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return wrap
    }

    private func makeSlider(min: Double, max: Double, value: Double, action: Selector) -> NSSlider {
        let s = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        s.isContinuous = true
        return s
    }

    // MARK: - Actions

    @objc private func onDemoChanged(_ sender: NSPopUpButton) {
        demo = MacDemoKind(rawValue: sender.indexOfSelectedItem) ?? .arcs
        applyDemo()
    }

    @objc private func onScale(_ sender: NSSlider) {
        userScale = Float(sender.doubleValue)
        globe.update { $0.scale = userScale }
    }

    @objc private func onBrightness(_ sender: NSSlider) {
        brightness = Float(sender.doubleValue)
        globe.update { $0.mapBrightness = brightness }
    }

    @objc private func onMarkerSize(_ sender: NSSlider) {
        markerSize = Float(sender.doubleValue)
        applyDemo()
    }

    @objc private func onSpinToggle(_ sender: NSSwitch) {
        autoSpin = (sender.state == .on)
    }

    @objc private func onPan(_ g: NSPanGestureRecognizer) {
        let t = g.translation(in: globe)
        let dx = Float(t.x) * 0.005
        let dy = Float(t.y) * 0.005
        phi -= dx
        theta = max(-1.2, min(1.2, theta - dy))
        g.setTranslation(.zero, in: globe)
        globe.update { $0.phi = self.phi; $0.theta = self.theta }
    }

    // MARK: - Demo data

    private func applyDemo() {
        let majorCities: [CobeMarker] = [
            .init(location: .init( 37.7595, -122.4367), size: markerSize, id: "sf"),
            .init(location: .init( 40.7128,  -74.0060), size: markerSize, id: "ny"),
            .init(location: .init( 51.5074,   -0.1278), size: markerSize, id: "lon"),
            .init(location: .init( 35.6762,  139.6503), size: markerSize, id: "tyo"),
            .init(location: .init(-33.8688,  151.2093), size: markerSize, id: "syd"),
            .init(location: .init(  1.3521,  103.8198), size: markerSize, id: "sg"),
            .init(location: .init( 19.4326,  -99.1332), size: markerSize, id: "mex"),
            .init(location: .init(-23.5505,  -46.6333), size: markerSize, id: "sao"),
        ]
        let arcs: [CobeArc] = [
            .init(from: .init(37.7595, -122.4367), to: .init(40.7128, -74.0060)),
            .init(from: .init(40.7128,  -74.0060), to: .init(51.5074, -0.1278)),
            .init(from: .init(51.5074,   -0.1278), to: .init(35.6762, 139.6503)),
            .init(from: .init(35.6762,  139.6503), to: .init(-33.8688, 151.2093)),
            .init(from: .init(-33.8688, 151.2093), to: .init(1.3521,  103.8198)),
            .init(from: .init(19.4326,  -99.1332), to: .init(-23.5505, -46.6333)),
        ]

        globe.update { o in
            o.scale = userScale
            o.mapSamples = 16_000
            o.mapBrightness = brightness
            o.diffuse = 3
            o.opacity = 1
            o.markerElevation = 0.05
            o.arcWidth = 1
            o.arcHeight = 0.3
            o.perspective = 0
            o.phi = phi
            o.theta = theta

            switch demo {
            case .basic:
                o.baseColor   = .init(1.0, 1.0, 1.0)
                o.markerColor = .init(1.0, 0.5, 0.0)
                o.glowColor   = .init(0.95, 0.95, 0.95)
                o.dark = 0
                o.markers = majorCities
                o.arcs = []
            case .dark:
                o.baseColor   = .init(0.3, 0.3, 0.3)
                o.markerColor = .init(0.1, 0.8, 1.0)
                o.glowColor   = .init(1.0, 1.0, 1.0)
                o.dark = 1
                o.markers = majorCities
                o.arcs = []
            case .glow:
                o.baseColor   = .init(0.15, 0.15, 0.25)
                o.markerColor = .init(1.0, 0.3, 0.8)
                o.glowColor   = .init(0.5, 0.3, 1.0)
                o.dark = 1
                o.diffuse = 1.2
                o.markers = majorCities
                o.arcs = []
            case .arcs:
                o.baseColor   = .init(0.2, 0.2, 0.3)
                o.markerColor = .init(1.0, 1.0, 0.2)
                o.glowColor   = .init(0.4, 0.6, 1.0)
                o.arcColor    = .init(0.3, 0.8, 1.0)
                o.dark = 1
                o.markers = majorCities
                o.arcs = arcs
            }
        }
    }

    // MARK: - Spin ticker

    private func startTicker() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        lastTick = CACurrentMediaTime()
    }

    private func stopTicker() {}

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastTick
        lastTick = now

        frameAccum += dt
        frameCount += 1
        if frameAccum >= 0.5 {
            let fps = Double(frameCount) / frameAccum
            fpsLabel.stringValue = String(format: "%.0f fps  •  scale %.2f  •  bright %.0f", fps, Double(userScale), Double(brightness))
            frameAccum = 0
            frameCount = 0
        }

        if autoSpin {
            phi += Float(dt) * 0.35
            globe.update { $0.phi = self.phi }
        } else {
            globe.update { _ in }
        }
    }
}
