import UIKit
import RealityKit
import SceneKit
import ModelIO

/// 3D fob view using RealityKit. Loads uguisu_placeholder.usdz from the app bundle when present,
/// maps tap = unlock and 700ms long-press = lock, and animates button depression (~1–2mm).
/// Falls back to FobPlaceholderView (2D) when the USDZ is not in the bundle.
final class FobRealityView: UIView {

    private let onTap: () -> Void
    private let onLongPress: () -> Void
    private var arView: ARView?
    private var buttonEntity: Entity?
    private var buttonRestPosition: SIMD3<Float>?
    private var fallbackView: FobPlaceholderView?
    private let depressionMm: Float = 2.0 / 1000.0

    init(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
        self.onTap = onTap
        self.onLongPress = onLongPress
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if arView == nil && fallbackView == nil {
            loadContent()
        }
    }

    private func loadContent() {
        guard let url = Bundle.main.url(forResource: "uguisu_placeholder", withExtension: "usdz") else {
            addFallback()
            return
        }
        do {
            let entity = try Entity.loadModel(contentsOf: url)
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(entity)
            let ar = ARView(frame: bounds)
            ar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            ar.environment.background = .color(.clear)
            ar.scene.anchors.append(anchor)
            arView = ar
            addSubview(ar)
            if let button = entity.findEntity(named: "button") {
                buttonEntity = button
                buttonRestPosition = button.position
            }
            setupGestures()
        } catch {
            addFallback()
        }
    }

    private func addFallback() {
        // Try to load a GLB via ModelIO/SceneKit as a better 3D fallback before using 2D placeholder
        if let glbUrl = Bundle.main.url(forResource: "uguisu_placeholder", withExtension: "glb") {
            do {
                // Prefer SceneKit's SCNSceneSource to load GLB; fall back to 2D placeholder if unsupported.
                if let sceneSource = SCNSceneSource(url: glbUrl, options: nil), let scene = sceneSource.scene(options: nil) {
                    let scnView = SCNView(frame: bounds)
                    scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    scnView.backgroundColor = .clear
                    scnView.scene = scene
                    scnView.allowsCameraControl = false
                    scnView.autoenablesDefaultLighting = true
                    addSubview(scnView)

                    // Try to find the button node by name
                    if let buttonNode = scene.rootNode.childNode(withName: "button", recursively: true) {
                        buttonRestPosition = SIMD3<Float>(Float(buttonNode.position.x), Float(buttonNode.position.y), Float(buttonNode.position.z))
                        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
                        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
                        long.minimumPressDuration = 0.7
                        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
                        pan.minimumNumberOfTouches = 1
                        pan.maximumNumberOfTouches = 1
                        scnView.addGestureRecognizer(tap)
                        scnView.addGestureRecognizer(long)
                        scnView.addGestureRecognizer(pan)
                        tap.require(toFail: long)

                        scnView.accessibilityElements = [buttonNode]
                    }
                    return
                }
                // successfully loaded via SCNSceneSource and returned
            } catch {
                // fall through to 2D placeholder
            }
        }

        let fob = FobPlaceholderView(onTap: onTap, onLongPress: onLongPress)
        fob.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fob)
        NSLayoutConstraint.activate([
            fob.topAnchor.constraint(equalTo: topAnchor),
            fob.leadingAnchor.constraint(equalTo: leadingAnchor),
            fob.trailingAnchor.constraint(equalTo: trailingAnchor),
            fob.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        fallbackView = fob
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        long.minimumPressDuration = 0.7
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        addGestureRecognizer(tap)
        addGestureRecognizer(long)
        tap.require(toFail: long)
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap()
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        if g.state == .began {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            onLongPress()
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            setButtonDepressed(true)
        case .ended, .cancelled:
            setButtonDepressed(false)
        default:
            break
        }
    }

    private func setButtonDepressed(_ depressed: Bool) {
        // RealityKit path
        if let button = buttonEntity, let rest = buttonRestPosition {
            let zOffset = depressed ? -depressionMm : 0
            button.position = SIMD3<Float>(rest.x, rest.y, rest.z + zOffset)
            return
        }
        // SceneKit fallback: find SCNView and node
        for sub in subviews {
            if let scn = sub as? SCNView, let elements = scn.accessibilityElements, let node = elements.first as? SCNNode, let rest = buttonRestPosition {
                let zOffset = depressed ? -CGFloat(depressionMm) : 0
                node.position.z = Float(rest.z) + Float(zOffset)
                return
            }
        }
    }
}
