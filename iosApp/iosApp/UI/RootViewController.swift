import UIKit
import Combine
import shared

/// Root container: shows Home or Settings, and the disconnect overlay when BLE is not connected.
final class RootViewController: UIViewController {

    private let bleService: IosBleProximityService
    private var cancellables = Set<AnyCancellable>()
    private var tapHintDismissed = false

    private let containerView = UIView()
    private let overlayView = DisconnectOverlayView()
    private var homeVC: HomeViewController?
    private var settingsVC: SettingsPlaceholderViewController?

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
        showHome()
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

    private func showHome() {
        settingsVC?.willMove(toParent: nil)
        settingsVC?.view.removeFromSuperview()
        settingsVC?.removeFromParent()
        settingsVC = nil

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
        addChild(home)
        containerView.addSubview(home.view)
        home.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            home.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            home.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            home.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            home.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        home.didMove(toParent: self)
    }

    private func showSettings() {
        homeVC?.willMove(toParent: nil)
        homeVC?.view.removeFromSuperview()
        homeVC?.removeFromParent()
        homeVC = nil

        let settings = SettingsPlaceholderViewController(onClose: { [weak self] in
            self?.showHome()
        })
        settingsVC = settings
        addChild(settings)
        containerView.addSubview(settings.view)
        settings.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            settings.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            settings.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            settings.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            settings.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        settings.didMove(toParent: self)
    }

    private func updateOverlay(connectionState: ConnectionState) {
        let show: Bool
        switch connectionState {
        case .connectedLocked, .connectedUnlocked: show = false
        default: show = true
        }
        overlayView.isHidden = !show
    }
}
