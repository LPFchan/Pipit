import UIKit
import Combine

#if canImport(shared)
import shared
#endif

/// Root container: shows Home or Settings, and the disconnect overlay when BLE is not connected.
final class RootViewController: UIViewController {

    private enum RootScreen {
        case onboarding
        case home
        case settings
    }

    private let bleService: IosBleProximityService
    private var cancellables = Set<AnyCancellable>()
    private var tapHintDismissed = false

    private let containerView = UIView()
    private let overlayView = DisconnectOverlayView()
    private var homeVC: HomeViewController?
    private var settingsVC: SettingsPlaceholderViewController?
    private var onboardingVC: OnboardingPlaceholderViewController?
    private var currentScreen: RootScreen = .onboarding

    #if canImport(shared)
    private let onboardingGate = OnboardingGate()
    #endif

    init(bleService: IosBleProximityService) {
        self.bleService = bleService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        showInitialScreen()
        view.addSubview(overlayView)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        bleService.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateOverlay(connectionState: state)
            }
            .store(in: &cancellables)
        updateOverlay(connectionState: bleService.connectionState)
    }

    private func showInitialScreen() {
        #if canImport(shared)
        if onboardingGate.hasAnyProvisionedKey() {
            showHome()
        } else {
            showOnboarding()
        }
        #else
        showOnboarding()
        #endif
    }

    private func clearCurrentChild() {
        [homeVC, settingsVC, onboardingVC].forEach { child in
            child?.willMove(toParent: nil)
            child?.view.removeFromSuperview()
            child?.removeFromParent()
        }
        homeVC = nil
        settingsVC = nil
        onboardingVC = nil
    }

    private func install(_ child: UIViewController) {
        addChild(child)
        containerView.addSubview(child.view)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        child.didMove(toParent: self)
        updateOverlay(connectionState: bleService.connectionState)
    }

    private func showOnboarding() {
        clearCurrentChild()
        currentScreen = .onboarding

        let onboarding = OnboardingPlaceholderViewController(
            bleService: bleService,
            onProvisioned: { [weak self] in self?.showHome() }
        )
        onboardingVC = onboarding
        install(onboarding)
    }

    private func showHome() {
        clearCurrentChild()
        currentScreen = .home

        let home = HomeViewController(
            onGearTap: { [weak self] in self?.showSettings() },
            onFobTap: { [weak self] in
                Task { await self?.bleService.sendUnlockCommand() }
            },
            onFobLongPress: { [weak self] in
                Task { await self?.bleService.sendLockCommand() }
            },
            showTapHint: !tapHintDismissed,
            onHintDismissed: { [weak self] in self?.tapHintDismissed = true }
        )
        homeVC = home
        install(home)
    }

    private func showSettings() {
        clearCurrentChild()
        currentScreen = .settings

        let settings = SettingsPlaceholderViewController(onClose: { [weak self] in
            self?.showHome()
        })
        settingsVC = settings
        install(settings)
    }

    private func updateOverlay(connectionState: ConnectionState) {
        guard currentScreen != .onboarding else {
            overlayView.isHidden = true
            return
        }

        let show: Bool
        switch connectionState {
        case .connectedLocked, .connectedUnlocked: show = false
        default: show = true
        }
        overlayView.isHidden = !show
    }
}
