import UIKit
import Cobe
import simd
import QuartzCore

enum DemoKind: Int, CaseIterable {
    case basic, dark, glow, emoji, arcs, gallery, card
    var title: String {
        switch self {
        case .basic:   return "Basic"
        case .dark:    return "Dark"
        case .glow:    return "Glow"
        case .emoji:   return "Emoji"
        case .arcs:    return "Arcs"
        case .gallery: return "Gallery"
        case .card:    return "Card"
        }
    }
    var icon: String {
        switch self {
        case .basic:   return "circle"
        case .dark:    return "moon.fill"
        case .glow:    return "sparkles"
        case .emoji:   return "face.smiling"
        case .arcs:    return "arrow.up.right"
        case .gallery: return "photo.on.rectangle"
        case .card:    return "rectangle.on.rectangle"
        }
    }
}

private struct Pin {
    let id: String
    let lat: Double
    let lon: Double
    let title: String
    let emoji: String
    let symbol: String
    let tint: UIColor
}

final class ViewController: UIViewController {

    // MARK: - State
    private var globe: CobeView!
    private var overlay: UIView!
    private var anchors: [String: UIView] = [:]
    private var displayLink: CADisplayLink?

    private var phi: Float = -1.4
    private var theta: Float = 0.25
    private var autoSpin = true
    private var demo: DemoKind = .emoji

    private var userScale: Float = 0.55
    private var brightness: Float = 6
    private var markerSize: Float = 0.05
    private var perspective3D: Bool = false
    private var stressMode: Bool = false

    // MARK: - UI
    private var menuButton: UIButton!
    private var inspector: UIView!
    private var fpsLabel: UILabel!
    private var perfLabel: UILabel!
    private var perfLabel2: UILabel!
    private var inspectorToggle: UIButton!
    private var scaleSlider: UISlider!
    private var brightnessSlider: UISlider!
    private var markerSizeSlider: UISlider!
    private var spinSwitch: UISwitch!
    private var depth3DSwitch: UISwitch!
    private var stressSlider: UISlider!
    private var stressCountLabel: UILabel!

    // Stress pool + animation tracking
    private struct StressItem {
        let id: String
        let location: SIMD2<Double>
        let baseSize: Float
        let color: SIMD3<Float>
        let emoji: String
        let symbol: String
        let tint: UIColor
        let title: String
        let arcTo: SIMD2<Double>
    }
    private var stressPool: [StressItem] = []
    private var stressById: [String: StressItem] = [:]
    private var activeStressIds: Set<String> = []
    private var spawnTimes: [String: CFTimeInterval] = [:]
    private var exitTimes: [String: CFTimeInterval] = [:]
    private let spawnDuration: CFTimeInterval = 0.45
    private let exitDuration: CFTimeInterval = 0.28

    // FPS tracking
    private var frameStamps: [CFTimeInterval] = []
    private var lastTickTime: CFTimeInterval = 0
    private var frameTimeMs: Double = 0

    private let emojiPins: [Pin] = [
        .init(id: "elephant",  lat: 20.0,    lon: 78.0,    title: "India",     emoji: "🐘", symbol: "leaf.fill",          tint: .systemGreen),
        .init(id: "dragon",    lat: 35.0,    lon: 104.0,   title: "China",     emoji: "🐉", symbol: "flame.fill",         tint: .systemRed),
        .init(id: "gamepad",   lat: 39.9,    lon: 116.4,   title: "Beijing",   emoji: "🎮", symbol: "gamecontroller.fill",tint: .systemPurple),
        .init(id: "tower",     lat: 35.6762, lon: 139.6503,title: "Tokyo",     emoji: "🗼", symbol: "building.2.fill",    tint: .systemPink),
        .init(id: "surfer",    lat: 21.3,    lon: -157.8,  title: "Hawaii",    emoji: "🏄", symbol: "wave.3.right",       tint: .systemBlue),
        .init(id: "taco",      lat: 19.4326, lon: -99.1332,title: "Mexico",    emoji: "🌮", symbol: "fork.knife",         tint: .systemOrange),
        .init(id: "koala",     lat: -27.0,   lon: 135.0,   title: "Australia", emoji: "🐨", symbol: "tree.fill",          tint: .systemTeal),
    ]

    private let galleryPins: [Pin] = [
        .init(id: "paris",  lat: 48.8584, lon: 2.2945,    title: "Paris",     emoji: "🗼", symbol: "building.columns.fill", tint: .systemPink),
        .init(id: "nyc",    lat: 40.6892, lon: -74.0445,  title: "New York",  emoji: "🗽", symbol: "building.2.crop.circle",tint: .systemBlue),
        .init(id: "sydney", lat: -33.8568,lon: 151.2153,  title: "Sydney",    emoji: "🇦🇺", symbol: "drop.fill",            tint: .systemTeal),
        .init(id: "wall",   lat: 40.4319, lon: 116.5704,  title: "Great Wall",emoji: "🇨🇳", symbol: "mountain.2.fill",      tint: .systemBrown),
        .init(id: "giza",   lat: 29.9792, lon: 31.1342,   title: "Giza",      emoji: "🐪", symbol: "triangle.fill",         tint: .systemYellow),
        .init(id: "rio",    lat: -22.9519,lon: -43.2105,  title: "Rio",       emoji: "🇧🇷", symbol: "figure.arms.open",     tint: .systemGreen),
        .init(id: "taj",    lat: 27.1751, lon: 78.0421,   title: "Agra",      emoji: "🕌", symbol: "moon.stars.fill",       tint: .systemPurple),
        .init(id: "london", lat: 51.5007, lon: -0.1246,   title: "London",    emoji: "🇬🇧", symbol: "clock.fill",           tint: .systemRed),
    ]

    private let randomNames = ["Aurora","Orion","Vega","Luna","Atlas","Nova","Iris","Echo","Sage","Lyra","Kai","Zen","Onyx","Rune","Sol","Faye","Quill","Pax","Vale","Wren"]

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupGlobe()
        setupOverlay()
        setupTopMenu()
        setupInspector()
        setupControls()
        setupGestures()
        applyDemo()
        startTick()
    }

    private func setupGlobe() {
        view.backgroundColor = .white
        globe = CobeView(frame: view.bounds, device: nil)
        globe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        globe.backgroundColor = .clear
        view.addSubview(globe)
    }

    private func setupOverlay() {
        overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        view.addSubview(overlay)

        // onProject runs from MTKView draw on main thread — no DispatchQueue needed.
        globe.cobe.onProject = { [weak self] marker, proj in
            guard let self = self, let id = marker.id, let v = self.anchors[id] else { return }

            // Cull off-globe and fully-transparent anchors
            if proj.alpha <= 0.001 {
                if !v.isHidden { v.isHidden = true }
                return
            }
            if v.isHidden { v.isHidden = false }

            // Disable implicit Core Animation transitions to prevent per-frame anim overhead
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            let w = self.overlay.bounds.width
            let h = self.overlay.bounds.height
            v.layer.position = CGPoint(x: proj.point.x * w, y: proj.point.y * h)

            var entrance: Float = 1.0
            if let spawn = self.spawnTimes[id] {
                let age = CACurrentMediaTime() - spawn
                let t = Float(min(1, max(0, age / self.spawnDuration)))
                entrance = 1.0 - (1.0 - t) * (1.0 - t)
            }
            v.layer.opacity = proj.alpha * entrance

            let depthScale: CGFloat = self.perspective3D
                ? CGFloat(0.55 + max(0, proj.depth) * 0.7)
                : 1.0
            let entranceScale = CGFloat(0.4 + 0.6 * entrance)
            let s = depthScale * entranceScale
            v.layer.transform = CATransform3DMakeScale(s, s, 1)

            CATransaction.commit()
        }
    }

    // MARK: - Top menu (dropdown picker)
    private func setupTopMenu() {
        menuButton = UIButton(type: .system)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.backgroundColor = UIColor(white: 1.0, alpha: 0.55)
        menuButton.layer.cornerRadius = 18
        menuButton.layer.borderWidth = 0.5
        menuButton.layer.borderColor = UIColor.systemGray3.cgColor
        menuButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        menuButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        menuButton.tintColor = .label
        menuButton.showsMenuAsPrimaryAction = true
        if #available(iOS 14, *) {
            menuButton.menu = buildDemoMenu()
        }
        updateMenuButtonTitle()
        view.addSubview(menuButton)

        NSLayoutConstraint.activate([
            menuButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            menuButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            menuButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @available(iOS 14, *)
    private func buildDemoMenu() -> UIMenu {
        let actions = DemoKind.allCases.map { kind in
            UIAction(title: kind.title,
                     image: UIImage(systemName: kind.icon),
                     state: kind == self.demo ? .on : .off) { [weak self] _ in
                guard let self = self else { return }
                self.demo = kind
                self.applyDemo()
                self.updateMenuButtonTitle()
                if #available(iOS 14, *) {
                    self.menuButton.menu = self.buildDemoMenu()
                }
            }
        }
        return UIMenu(title: "Globe style", children: actions)
    }

    private func updateMenuButtonTitle() {
        let chevron = "  ▾"
        menuButton.setTitle(demo.title + chevron, for: .normal)
    }

    // MARK: - Inspector
    private func setupInspector() {
        inspector = UIView()
        inspector.translatesAutoresizingMaskIntoConstraints = false
        inspector.backgroundColor = UIColor(white: 0.0, alpha: 0.72)
        inspector.layer.cornerRadius = 10
        inspector.layer.borderWidth = 0.5
        inspector.layer.borderColor = UIColor(white: 1, alpha: 0.2).cgColor

        fpsLabel = UILabel()
        fpsLabel.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        fpsLabel.textColor = .systemGreen
        fpsLabel.text = "-- fps"

        perfLabel = UILabel()
        perfLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        perfLabel.textColor = .white
        perfLabel.text = "frame -- ms"

        perfLabel2 = UILabel()
        perfLabel2.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        perfLabel2.textColor = .white
        perfLabel2.text = "M:0  A:0"

        let stack = UIStackView(arrangedSubviews: [fpsLabel, perfLabel, perfLabel2])
        stack.axis = .vertical
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        inspector.addSubview(stack)
        view.addSubview(inspector)

        inspectorToggle = UIButton(type: .system)
        inspectorToggle.translatesAutoresizingMaskIntoConstraints = false
        inspectorToggle.setImage(UIImage(systemName: "info.circle.fill"), for: .normal)
        inspectorToggle.tintColor = .systemGray
        inspectorToggle.backgroundColor = UIColor(white: 1.0, alpha: 0.55)
        inspectorToggle.layer.cornerRadius = 14
        inspectorToggle.addTarget(self, action: #selector(toggleInspector), for: .touchUpInside)
        view.addSubview(inspectorToggle)

        NSLayoutConstraint.activate([
            inspector.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 52),
            inspector.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            inspector.widthAnchor.constraint(equalToConstant: 118),

            stack.topAnchor.constraint(equalTo: inspector.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: inspector.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: inspector.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: inspector.bottomAnchor, constant: -6),

            inspectorToggle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            inspectorToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            inspectorToggle.widthAnchor.constraint(equalToConstant: 28),
            inspectorToggle.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @objc private func toggleInspector() {
        inspector.isHidden.toggle()
    }

    // MARK: - Controls
    private func setupControls() {
        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = UIColor(white: 1.0, alpha: 0.85)
        panel.layer.cornerRadius = 16
        panel.layer.borderWidth = 0.5
        panel.layer.borderColor = UIColor.systemGray4.cgColor
        view.addSubview(panel)

        let hint = UILabel()
        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = .systemGray
        hint.text = "drag = rotate · tap = pause · pinch = zoom"

        let (zoomRow, zSlider)   = makeSliderRow(title: "Zoom",   min: 0.3, max: 2.5, value: userScale)
        scaleSlider = zSlider
        scaleSlider.addTarget(self, action: #selector(onScale), for: .valueChanged)

        let (brightRow, bSlider) = makeSliderRow(title: "Map",    min: 1,   max: 12,  value: brightness)
        brightnessSlider = bSlider
        brightnessSlider.addTarget(self, action: #selector(onBrightness), for: .valueChanged)

        let (sizeRow, sSlider)   = makeSliderRow(title: "Marker", min: 0.005, max: 0.12, value: markerSize)
        markerSizeSlider = sSlider
        markerSizeSlider.addTarget(self, action: #selector(onMarkerSize), for: .valueChanged)

        spinSwitch = UISwitch()
        spinSwitch.isOn = autoSpin
        spinSwitch.addTarget(self, action: #selector(onSpin), for: .valueChanged)
        let spinLb = UILabel(); spinLb.text = "Spin"; spinLb.font = .systemFont(ofSize: 13, weight: .medium)

        depth3DSwitch = UISwitch()
        depth3DSwitch.isOn = perspective3D
        depth3DSwitch.addTarget(self, action: #selector(on3D), for: .valueChanged)
        let depth3DLb = UILabel(); depth3DLb.text = "3D"; depth3DLb.font = .systemFont(ofSize: 13, weight: .medium)

        let togglesRow = UIStackView(arrangedSubviews: [spinLb, spinSwitch, UIView(), depth3DLb, depth3DSwitch])
        togglesRow.axis = .horizontal
        togglesRow.spacing = 6
        togglesRow.alignment = .center

        // Stress slider row
        let stressLb = UILabel()
        stressLb.text = "Stress"
        stressLb.font = .systemFont(ofSize: 13, weight: .semibold)
        stressLb.textColor = .systemPurple
        stressLb.widthAnchor.constraint(equalToConstant: 54).isActive = true

        stressSlider = UISlider()
        stressSlider.minimumValue = 0
        stressSlider.maximumValue = 500
        stressSlider.value = 0
        stressSlider.minimumTrackTintColor = .systemPurple
        stressSlider.addTarget(self, action: #selector(onStressSlider), for: .valueChanged)

        stressCountLabel = UILabel()
        stressCountLabel.text = "0"
        stressCountLabel.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        stressCountLabel.textColor = .systemPurple
        stressCountLabel.textAlignment = .right
        stressCountLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true

        let resetBtn = UIButton(type: .system)
        resetBtn.setTitle("Reset", for: .normal)
        resetBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        resetBtn.tintColor = .systemPurple
        resetBtn.layer.borderWidth = 1
        resetBtn.layer.borderColor = UIColor.systemPurple.cgColor
        resetBtn.layer.cornerRadius = 8
        resetBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        resetBtn.addTarget(self, action: #selector(onReset), for: .touchUpInside)

        let actionRow = UIStackView(arrangedSubviews: [stressLb, stressSlider, stressCountLabel, resetBtn])
        actionRow.axis = .horizontal
        actionRow.spacing = 6
        actionRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [hint, zoomRow, brightRow, sizeRow, togglesRow, actionRow])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),
        ])
    }

    private func makeSliderRow(title: String, min: Float, max: Float, value: Float) -> (UIView, UISlider) {
        let lb = UILabel()
        lb.text = title
        lb.font = .systemFont(ofSize: 13, weight: .medium)
        lb.widthAnchor.constraint(equalToConstant: 54).isActive = true
        let slider = UISlider()
        slider.minimumValue = min; slider.maximumValue = max; slider.value = value
        let row = UIStackView(arrangedSubviews: [lb, slider])
        row.axis = .horizontal; row.spacing = 8
        return (row, slider)
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        globe.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap))
        globe.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        globe.addGestureRecognizer(pinch)
    }

    private func startTick() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    // MARK: - Anchor builders
    private func clearAnchors() {
        anchors.values.forEach { $0.removeFromSuperview() }
        anchors.removeAll()
    }

    private func buildEmojiAnchors() {
        for p in emojiPins {
            let lb = UILabel()
            lb.text = p.emoji
            lb.font = .systemFont(ofSize: 30)
            lb.textAlignment = .center
            lb.sizeToFit()
            overlay.addSubview(lb)
            anchors[p.id] = lb
        }
    }

    private func buildGalleryAnchors() {
        for p in galleryPins {
            let card = makePhotoCard(symbol: p.symbol, title: p.title, tint: p.tint)
            overlay.addSubview(card)
            anchors[p.id] = card
        }
    }

    private func buildCardAnchors() {
        for p in galleryPins {
            let card = makeInfoCard(title: p.title, lat: p.lat, lon: p.lon, emoji: p.emoji)
            overlay.addSubview(card)
            anchors[p.id] = card
        }
    }

    private func makePhotoCard(symbol: String, title: String, tint: UIColor) -> UIView {
        let W: CGFloat = 72, H: CGFloat = 86
        let v = UIView(frame: CGRect(x: 0, y: 0, width: W, height: H))
        v.backgroundColor = .white
        v.layer.cornerRadius = 10
        v.layer.borderColor = UIColor.systemGray5.cgColor
        v.layer.borderWidth = 0.5

        let img = UIImageView(frame: CGRect(x: 6, y: 6, width: W - 12, height: 56))
        img.contentMode = .scaleAspectFit
        img.tintColor = .white
        img.image = UIImage(systemName: symbol)
        img.backgroundColor = tint
        img.layer.cornerRadius = 8
        img.clipsToBounds = true
        v.addSubview(img)

        let cap = UILabel(frame: CGRect(x: 4, y: 66, width: W - 8, height: 14))
        cap.text = title
        cap.font = .systemFont(ofSize: 10, weight: .semibold)
        cap.textColor = .label
        cap.textAlignment = .center
        v.addSubview(cap)

        v.layer.shouldRasterize = true
        v.layer.rasterizationScale = UIScreen.main.scale
        return v
    }

    private func makeInfoCard(title: String, lat: Double, lon: Double, emoji: String) -> UIView {
        let W: CGFloat = 120, H: CGFloat = 44
        let v = UIView(frame: CGRect(x: 0, y: 0, width: W, height: H))
        v.backgroundColor = UIColor(white: 1.0, alpha: 0.96)
        v.layer.cornerRadius = 10
        v.layer.borderWidth = 0.5
        v.layer.borderColor = UIColor.systemGray4.cgColor

        let icon = UILabel(frame: CGRect(x: 8, y: 10, width: 26, height: 24))
        icon.text = emoji
        icon.font = .systemFont(ofSize: 22)
        v.addSubview(icon)

        let nameLb = UILabel(frame: CGRect(x: 38, y: 4, width: W - 50, height: 18))
        nameLb.text = title
        nameLb.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLb.textColor = .label
        v.addSubview(nameLb)

        let coordLb = UILabel(frame: CGRect(x: 38, y: 22, width: W - 50, height: 14))
        coordLb.text = String(format: "%.2f°, %.2f°", lat, lon)
        coordLb.font = .systemFont(ofSize: 10)
        coordLb.textColor = .secondaryLabel
        v.addSubview(coordLb)

        let dot = UIView(frame: CGRect(x: W - 12, y: (H - 6) / 2, width: 6, height: 6))
        dot.backgroundColor = .systemPink
        dot.layer.cornerRadius = 3
        v.addSubview(dot)

        v.layer.shouldRasterize = true
        v.layer.rasterizationScale = UIScreen.main.scale
        return v
    }

    // MARK: - Demo configuration
    private func applyDemo() {
        clearAnchors()
        stressMode = false

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
            o.perspective = perspective3D ? 1 : 0

            switch demo {
            case .basic:
                view.backgroundColor = .white
                o.baseColor   = .init(1.0, 1.0, 1.0)
                o.markerColor = .init(1.0, 0.5, 0.0)
                o.glowColor   = .init(0.95, 0.95, 0.95)
                o.dark = 0
                o.markers = majorCities
                o.arcs = []
            case .dark:
                view.backgroundColor = .black
                o.baseColor   = .init(0.3, 0.3, 0.3)
                o.markerColor = .init(0.1, 0.8, 1.0)
                o.glowColor   = .init(1.0, 1.0, 1.0)
                o.dark = 1
                o.markers = majorCities
                o.arcs = []
            case .glow:
                view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1)
                o.baseColor   = .init(0.15, 0.15, 0.25)
                o.markerColor = .init(1.0, 0.3, 0.8)
                o.glowColor   = .init(0.5, 0.3, 1.0)
                o.dark = 1
                o.diffuse = 1.2
                o.markers = majorCities
                o.arcs = []
            case .emoji:
                view.backgroundColor = .white
                o.baseColor   = .init(1.0, 1.0, 1.0)
                o.markerColor = .init(0.9, 0.2, 0.55)
                o.glowColor   = .init(0.95, 0.95, 0.95)
                o.dark = 0
                o.markers = emojiPins.map { p in
                    CobeMarker(location: .init(p.lat, p.lon), size: markerSize, id: p.id)
                }
                o.arcs = []
                buildEmojiAnchors()
            case .arcs:
                view.backgroundColor = .black
                o.baseColor   = .init(0.2, 0.2, 0.3)
                o.markerColor = .init(1.0, 1.0, 0.2)
                o.glowColor   = .init(0.4, 0.6, 1.0)
                o.arcColor    = .init(0.3, 0.8, 1.0)
                o.dark = 1
                o.markers = majorCities
                o.arcs = arcs
            case .gallery:
                view.backgroundColor = UIColor(white: 0.97, alpha: 1)
                o.baseColor   = .init(0.95, 0.95, 0.97)
                o.markerColor = .init(0.95, 0.3, 0.5)
                o.glowColor   = .init(0.9, 0.9, 0.95)
                o.dark = 0
                o.markers = galleryPins.map { p in
                    CobeMarker(location: .init(p.lat, p.lon), size: 0.025, id: p.id)
                }
                o.arcs = []
                buildGalleryAnchors()
            case .card:
                view.backgroundColor = .white
                o.baseColor   = .init(1.0, 1.0, 1.0)
                o.markerColor = .init(1.0, 0.2, 0.5)
                o.glowColor   = .init(0.95, 0.95, 0.95)
                o.dark = 0
                o.markers = galleryPins.map { p in
                    CobeMarker(location: .init(p.lat, p.lon), size: 0.03, id: p.id)
                }
                o.arcs = []
                buildCardAnchors()
            }
            o.theta = theta
            o.phi = phi
        }
    }

    // MARK: - Stress test pool (stable, slider-driven)
    private func generateStressPool() {
        let emojiPool = ["🐘","🐉","🎮","🗼","🏄","🌮","🐨","🐱","🦁","🐯","🐼","🐧","🦄","🍕","🍔","🍣","🚀","⭐️","🎵","🎨","🌵","🐳","🌸","⚡️","🔥","💎","🎯","🍩","🛸","🏝"]
        let symbolPool = ["building.columns.fill","mountain.2.fill","drop.fill","sparkles","leaf.fill","flame.fill","sun.max.fill","moon.stars.fill","wave.3.right","star.fill","music.note","airplane","bolt.fill","cloud.fill"]
        let tintPool: [UIColor] = [.systemPink, .systemBlue, .systemGreen, .systemPurple, .systemTeal, .systemOrange, .systemRed, .systemYellow, .systemBrown, .systemIndigo]

        stressPool.removeAll(keepingCapacity: true)
        stressById.removeAll()
        for i in 0..<500 {
            let item = StressItem(
                id: "rnd\(i)",
                location: .init(Double.random(in: -78...78), Double.random(in: -180...180)),
                baseSize: Float.random(in: 0.005...0.018),
                color: .init(Float.random(in: 0.3...1.0),
                             Float.random(in: 0.3...1.0),
                             Float.random(in: 0.3...1.0)),
                emoji: emojiPool.randomElement()!,
                symbol: symbolPool.randomElement()!,
                tint: tintPool.randomElement()!,
                title: randomNames.randomElement()!,
                arcTo: .init(Double.random(in: -78...78), Double.random(in: -180...180))
            )
            stressPool.append(item)
            stressById[item.id] = item
        }
    }

    @objc private func onStressSlider() {
        if stressPool.isEmpty { generateStressPool() }
        let target = Int(stressSlider.value)
        stressCountLabel.text = "\(target)"

        if !stressMode {
            stressMode = true
            clearAnchors()
            spawnTimes.removeAll()
            exitTimes.removeAll()
            activeStressIds.removeAll()
        }

        let now = CACurrentMediaTime()
        let newActive = Set(stressPool.prefix(target).map { $0.id })
        let added = newActive.subtracting(activeStressIds)
        let removed = activeStressIds.subtracting(newActive)
        activeStressIds = newActive

        // Removed ids: start exit timer + zoom-fade anchor view
        for id in removed {
            exitTimes[id] = now
            spawnTimes.removeValue(forKey: id)
            if let v = anchors[id] {
                anchors.removeValue(forKey: id)
                UIView.animate(withDuration: exitDuration,
                               delay: 0,
                               options: [.curveEaseOut, .allowUserInteraction],
                               animations: {
                    v.alpha = 0
                    v.transform = v.transform.scaledBy(x: 1.8, y: 1.8)
                }, completion: { _ in v.removeFromSuperview() })
            }
        }

        // Added ids: spawn time + create anchor
        for id in added {
            guard let it = stressById[id] else { continue }
            spawnTimes[id] = now
            switch demo {
            case .emoji:
                let lb = UILabel()
                lb.text = it.emoji
                lb.font = .systemFont(ofSize: 22)
                lb.sizeToFit()
                lb.alpha = 0
                overlay.addSubview(lb)
                anchors[it.id] = lb
            case .gallery:
                let card = makePhotoCard(symbol: it.symbol, title: it.title, tint: it.tint)
                card.alpha = 0
                overlay.addSubview(card)
                anchors[it.id] = card
            case .card:
                let card = makeInfoCard(title: it.title,
                                        lat: it.location.x, lon: it.location.y,
                                        emoji: it.emoji)
                card.alpha = 0
                overlay.addSubview(card)
                anchors[it.id] = card
            default: break
            }
        }
        rebuildStressMarkers()
    }

    private func rebuildStressMarkers() {
        let now = CACurrentMediaTime()
        var markers: [CobeMarker] = []
        markers.reserveCapacity(activeStressIds.count + exitTimes.count)
        var arcs: [CobeArc] = []

        // Active markers with entrance easing
        for id in activeStressIds {
            guard let it = stressById[id] else { continue }
            var mul: Float = 1.0
            if let spawn = spawnTimes[id] {
                let age = now - spawn
                let t = Float(min(1.0, max(0.0, age / spawnDuration)))
                mul = 1.0 - (1.0 - t) * (1.0 - t)
                if t >= 1 { spawnTimes.removeValue(forKey: id) }
            }
            appendStressMarker(item: it, sizeMul: mul, fullVisible: mul > 0.6,
                               markers: &markers, arcs: &arcs)
        }

        // Exiting markers: grow + fade (size grows, no shader alpha, but shader fade scales w/ size)
        var finished: [String] = []
        for (id, ex) in exitTimes {
            let age = now - ex
            if age >= exitDuration { finished.append(id); continue }
            guard let it = stressById[id] else { continue }
            let t = Float(age / exitDuration)
            // Grow size 1.0 → 1.9 over duration. Past midway, taper shader visibility via tiny size.
            let grow: Float = 1.0 + 0.9 * t
            // Apply implicit fade by stepping size DOWN as t approaches 1 (last 30% shrinks toward 0 → invisible)
            let lateFade: Float = t < 0.7 ? 1.0 : max(0, 1.0 - (t - 0.7) / 0.3)
            let mul: Float = grow * lateFade
            appendStressMarker(item: it, sizeMul: mul, fullVisible: false,
                               markers: &markers, arcs: &arcs)
        }
        for id in finished { exitTimes.removeValue(forKey: id) }

        globe.update { o in
            o.markers = markers
            o.arcs = arcs
        }
    }

    private func appendStressMarker(item it: StressItem,
                                    sizeMul: Float,
                                    fullVisible: Bool,
                                    markers: inout [CobeMarker],
                                    arcs: inout [CobeArc]) {
        switch demo {
        case .basic, .dark, .glow:
            markers.append(CobeMarker(location: it.location,
                                      size: it.baseSize * sizeMul,
                                      color: it.color, id: it.id))
        case .emoji:
            markers.append(CobeMarker(location: it.location,
                                      size: 0.012 * sizeMul, id: it.id))
        case .gallery:
            markers.append(CobeMarker(location: it.location,
                                      size: 0.010 * sizeMul, id: it.id))
        case .card:
            markers.append(CobeMarker(location: it.location,
                                      size: 0.012 * sizeMul, id: it.id))
        case .arcs:
            markers.append(CobeMarker(location: it.location,
                                      size: 0.008 * sizeMul,
                                      color: it.color, id: it.id))
            if fullVisible {
                arcs.append(CobeArc(from: it.location, to: it.arcTo,
                                    color: it.color, id: "arc_\(it.id)"))
            }
        }
    }

    @objc private func onReset() {
        stressMode = false
        stressSlider.value = 0
        stressCountLabel.text = "0"
        spawnTimes.removeAll()
        exitTimes.removeAll()
        activeStressIds.removeAll()
        applyDemo()
    }

    // MARK: - Actions
    @objc private func onScale() {
        userScale = scaleSlider.value
        globe.update { o in o.scale = userScale }
    }
    @objc private func onBrightness() {
        brightness = brightnessSlider.value
        globe.update { o in o.mapBrightness = brightness }
    }
    @objc private func onMarkerSize() {
        markerSize = markerSizeSlider.value
        if !stressMode { applyDemo() }
    }
    @objc private func onSpin() { autoSpin = spinSwitch.isOn }
    @objc private func on3D() {
        perspective3D = depth3DSwitch.isOn
        globe.update { o in o.perspective = perspective3D ? 1 : 0 }
    }
    @objc private func onTap() {
        autoSpin.toggle()
        spinSwitch.isOn = autoSpin
    }
    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            autoSpin = false; spinSwitch.isOn = false
        case .changed:
            let t = g.translation(in: view)
            phi += Float(t.x) * 0.006
            theta -= Float(t.y) * 0.006
            theta = max(-1.4, min(1.4, theta))
            g.setTranslation(.zero, in: view)
        default: break
        }
    }
    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .changed {
            userScale *= Float(g.scale)
            userScale = max(0.3, min(2.5, userScale))
            scaleSlider.value = userScale
            globe.update { o in o.scale = userScale }
            g.scale = 1.0
        }
    }
    @objc private func tick() {
        if autoSpin { phi += 0.004 }

        // While stress active, rebuild markers each frame to animate spawn/exit
        if stressMode && (!spawnTimes.isEmpty || !exitTimes.isEmpty) {
            rebuildStressMarkers()
        }
        globe.update { o in o.phi = phi; o.theta = theta }
        updateInspector()
    }

    private func updateInspector() {
        let now = CACurrentMediaTime()
        if lastTickTime > 0 {
            frameTimeMs = (now - lastTickTime) * 1000
        }
        lastTickTime = now
        frameStamps.append(now)
        while let f = frameStamps.first, now - f > 1 { frameStamps.removeFirst() }
        let fps = frameStamps.count
        fpsLabel.text = "\(fps) fps"
        fpsLabel.textColor = fps >= 55 ? .systemGreen : (fps >= 30 ? .systemYellow : .systemRed)
        perfLabel.text = String(format: "frame %.1f ms", frameTimeMs)
        let mc = globe.cobe.options.markers.count
        let ac = globe.cobe.options.arcs.count
        perfLabel2.text = "M:\(mc)  A:\(ac)"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if CommandLine.arguments.contains("--gallery") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.demo = .gallery
                self.updateMenuButtonTitle()
                if #available(iOS 14, *) { self.menuButton.menu = self.buildDemoMenu() }
                self.applyDemo()
            }
        }
        if CommandLine.arguments.contains("--stress") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.stressSlider.value = 300
                self.onStressSlider()
            }
        }
        if CommandLine.arguments.contains("--exit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.stressSlider.value = 300
                self.onStressSlider()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self = self else { return }
                self.stressSlider.value = 60
                self.onStressSlider()
            }
        }
    }

    deinit { displayLink?.invalidate() }
}
