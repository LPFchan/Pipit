import UIKit
import RealityKit
import SceneKit
import CoreMotion
import AVFoundation

/// 3D fob view using RealityKit. Loads uguisu_placeholder.usdz from the app bundle when present,
/// maps tap = unlock and 700ms long-press = lock, and animates button depression (~1–2mm).
/// Falls back to FobPlaceholderView (2D) when the USDZ is not in the bundle.
final class FobRealityView: UIView {

    private let onTap: () -> Void
    private let onLongPress: () -> Void
    private var arView: ARView?
    private var rootEntity: Entity?
    private var buttonEntity: Entity?
    private var buttonRestPosition: SIMD3<Float>?
    private var ledEntity: ModelEntity?
    private var ledOriginalMaterial: Material?
    
    private var fallbackView: FobPlaceholderView?
    private let depressionMm: Float = 2.0 / 1000.0
    
    private let motionManager = CMMotionManager()
    private var unlockAudioPlayer: AVAudioPlayer?
    private var lockAudioPlayer: AVAudioPlayer?

    init(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
        self.onTap = onTap
        self.onLongPress = onLongPress
        super.init(frame: .zero)
        setupAudio()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    private func setupAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        // Stubs for real audio files
        if let unlockUrl = Bundle.main.url(forResource: "unlock_click", withExtension: "caf") {
            unlockAudioPlayer = try? AVAudioPlayer(contentsOf: unlockUrl)
            unlockAudioPlayer?.prepareToPlay()
        }
        if let lockUrl = Bundle.main.url(forResource: "lock_clunk", withExtension: "caf") {
            lockAudioPlayer = try? AVAudioPlayer(contentsOf: lockUrl)
            lockAudioPlayer?.prepareToPlay()
        }
    }

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
            rootEntity = entity
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
            
            if let led = entity.findEntity(named: "led_rgb") as? ModelEntity {
                ledEntity = led
                ledOriginalMaterial = led.model?.materials.first
                // Default to off
                var mat = SimpleMaterial(color: .black, isMetallic: false)
                led.model?.materials = [mat]
            }
            
            setupGestures()
            setupParallax()
        } catch {
            addFallback()
        }
    }
    
    private func setupParallax() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self = self, let motion = motion, let root = self.rootEntity else { return }
                
                // ±5 degrees max mapped from roll and pitch
                let maxAngle: Float = 5.0 * .pi / 180.0
                
                // Base orientation is upright, map phone tilt to visual tilt
                let pitch = Float(motion.attitude.pitch)
                let roll = Float(motion.attitude.roll)
                
                let cx = max(-maxAngle, min(maxAngle, pitch))
                let cy = max(-maxAngle, min(maxAngle, roll))
                
                root.transform.rotation = simd_quatf(angle: cx, axis: SIMD3<Float>(1, 0, 0)) * simd_quatf(angle: cy, axis: SIMD3<Float>(0, 1, 0))
            }
        }
    }

    private func addFallback() {
        // Try to load a GLB via ModelIO/SceneKit as a better 3D fallback before using 2D placeholder
        if let glbUrl = Bundle.main.url(forResource: "uguisu_placeholder", withExtension: "glb") {
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
        tap.numberOfTapsRequired = 1
        
        let tripleTap = UITapGestureRecognizer(target: self, action: #selector(handleTripleTap(_:)))
        tripleTap.numberOfTapsRequired = 3
        tap.require(toFail: tripleTap)
        
        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        long.minimumPressDuration = 0.7
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        
        addGestureRecognizer(pan)
        addGestureRecognizer(tripleTap)
        addGestureRecognizer(tap)
        addGestureRecognizer(long)
        
        tap.require(toFail: long)
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        if let player = unlockAudioPlayer {
            player.play()
        } else {
            AudioServicesPlaySystemSound(1104) // keyboard press click fallback
        }
        
        flashLED(color: .green)
        onTap()
    }
    
    @objc private func handleTripleTap(_ g: UITapGestureRecognizer) {
        let impact = UIImpactFeedbackGenerator(style: .rigid)
        impact.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { impact.impactOccurred() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { impact.impactOccurred() }
        
        flashLED(color: .blue, count: 3)
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        if g.state == .began {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            
            if let player = lockAudioPlayer {
                player.play()
            } else {
                AudioServicesPlaySystemSound(1105) // alternate click fallback
            }
            
            flashLED(color: .red)
            onLongPress()
        }
    }
    
    private func flashLED(color: UIColor, count: Int = 1) {
        guard let led = ledEntity else { return }
        
        func playFlashCycle(remaining: Int) {
            if remaining <= 0 { return }
            
            var mat = SimpleMaterial(color: color, isMetallic: false)
            led.model?.materials = [mat]
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                var offMat = SimpleMaterial(color: .black, isMetallic: false)
                led.model?.materials = [offMat]
                
                if remaining > 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        playFlashCycle(remaining: remaining - 1)
                    }
                }
            }
        }
        
        playFlashCycle(remaining: count)
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
