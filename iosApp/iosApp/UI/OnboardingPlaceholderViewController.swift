import UIKit
import Combine
import AVFoundation
import Security

#if canImport(shared)
import shared
#endif

private struct ProvisioningSuccess {
    let slotId: Int
    let counter: UInt32
    let name: String
}

private struct PendingProvisioningMaterial {
    let slotId: Int
    let key: Data
    let counter: UInt32
    let name: String
    let statusText: String
}

private enum ParsedProvisioningPayload {
    case guest(slotId: Int, key: Data, counter: UInt32, name: String)
    case encrypted(slotId: Int, salt: Data, encryptedKey: Data, counter: UInt32, name: String)
}

private enum ProvisioningQrParseError: LocalizedError {
    case missingField(String)
    case invalidField(String, String)
    case unsupportedVariant(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let field):
            return "Missing required field: \(field)"
        case .invalidField(let field, let detail):
            return "Invalid \(field): \(detail)"
        case .unsupportedVariant(let detail):
            return detail
        }
    }
}

/// Temporary onboarding container with camera scan, PIN entry, recovery read path, and success handoff.
final class OnboardingPlaceholderViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    private enum OnboardingState {
        case camera
        case pin
        case importing
        case recovery
        case locationPermission
        case success
    }

    private enum RecoveryState {
        case waitingForWindowOpen
        case connecting
        case loadingSlots
        case ownerProof
        case recovering
        case slotPicker
        case error
    }

    private let bleService: IosBleProximityService
    private let onProvisioned: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var recoveryTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let cameraQueue = DispatchQueue(label: "com.immogen.pipit.onboarding.camera")

    private var onboardingState: OnboardingState = .camera {
        didSet { updateUiForState() }
    }
    private var recoveryState: RecoveryState = .waitingForWindowOpen {
        didSet { updateUiForState() }
    }
    private var recoverySlots: [BleManagementSlot] = [] {
        didSet { rebuildSlotsContent() }
    }
    private var successOverviewSlots: [BleManagementSlot] = [] {
        didSet { rebuildSlotsContent() }
    }
    private var selectedSlotId: Int? {
        didSet {
            updateSlotSelectionUi()
            updateStatusText()
        }
    }
    private var recoveryErrorMessage: String? {
        didSet { errorLabel.text = recoveryErrorMessage }
    }
    private var scanErrorMessage: String? {
        didSet { errorLabel.text = scanErrorMessage }
    }
    private var pinErrorMessage: String? {
        didSet { errorLabel.text = pinErrorMessage }
    }
    private var pendingEncryptedPayload: ParsedProvisioningPayload?
    private var pendingProvisioningMaterial: PendingProvisioningMaterial?
    private var provisioningSuccess: ProvisioningSuccess?
    private var hasPlayedSuccessAnimation = false
    private var successParticles: [UIView] = []
    private var pinCode = "" {
        didSet { updatePinUi() }
    }
    private var isProvisioningInFlight = false {
        didSet { updatePrimaryButtonState() }
    }
    private var isScanLocked = false

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let successAnimationView = UIView()
    private let successSymbolLabel = UILabel()
    private let cameraPlaceholderView = UIView()
    private let viewfinderFrame = UIView()
    private let viewfinderHintLabel = UILabel()
    private let bodyLabel = UILabel()
    private let pinBoxesStack = UIStackView()
    private var pinBoxLabels: [UILabel] = []
    private let pinTextField = UITextField()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()
    private let slotsStack = UIStackView()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)

#if canImport(shared)
    private let keyStore = KeyStoreManager()
#endif

    init(bleService: IosBleProximityService, onProvisioned: @escaping () -> Void) {
        self.bleService = bleService
        self.onProvisioned = onProvisioned
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        recoveryTask?.cancel()
        importTask?.cancel()
        bleService.stopWindowOpenScan()
        bleService.disconnectManagement()
        stopCameraSession()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        configureLayout()
        bindBleState()
        updateUiForState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCameraSessionForCurrentState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCameraSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraPlaceholderView.bounds
        if !successAnimationView.isHidden {
            layoutSuccessParticlesAtCenter()
        }
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])

        titleLabel.font = .preferredFont(forTextStyle: .title1)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        contentStack.addArrangedSubview(titleLabel)

        successAnimationView.translatesAutoresizingMaskIntoConstraints = false
        successAnimationView.isHidden = true
        NSLayoutConstraint.activate([
            successAnimationView.heightAnchor.constraint(equalToConstant: 140)
        ])
        contentStack.addArrangedSubview(successAnimationView)

        successSymbolLabel.translatesAutoresizingMaskIntoConstraints = false
        successSymbolLabel.text = "✓"
        successSymbolLabel.font = .systemFont(ofSize: 54, weight: .semibold)
        successSymbolLabel.textColor = view.tintColor
        successSymbolLabel.alpha = 0
        successAnimationView.addSubview(successSymbolLabel)
        NSLayoutConstraint.activate([
            successSymbolLabel.centerXAnchor.constraint(equalTo: successAnimationView.centerXAnchor),
            successSymbolLabel.centerYAnchor.constraint(equalTo: successAnimationView.centerYAnchor)
        ])

        cameraPlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        cameraPlaceholderView.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.35)
        cameraPlaceholderView.layer.cornerRadius = 28
        cameraPlaceholderView.layer.borderWidth = 1
        cameraPlaceholderView.layer.borderColor = UIColor.separator.cgColor
        cameraPlaceholderView.layer.masksToBounds = true
        NSLayoutConstraint.activate([
            cameraPlaceholderView.heightAnchor.constraint(equalToConstant: 360)
        ])
        contentStack.addArrangedSubview(cameraPlaceholderView)

        viewfinderFrame.translatesAutoresizingMaskIntoConstraints = false
        viewfinderFrame.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.12)
        viewfinderFrame.layer.cornerRadius = 24
        viewfinderFrame.layer.borderWidth = 2
        viewfinderFrame.layer.borderColor = UIColor.white.cgColor
        cameraPlaceholderView.addSubview(viewfinderFrame)
        NSLayoutConstraint.activate([
            viewfinderFrame.widthAnchor.constraint(equalToConstant: 220),
            viewfinderFrame.heightAnchor.constraint(equalToConstant: 220),
            viewfinderFrame.centerXAnchor.constraint(equalTo: cameraPlaceholderView.centerXAnchor),
            viewfinderFrame.centerYAnchor.constraint(equalTo: cameraPlaceholderView.centerYAnchor)
        ])

        viewfinderHintLabel.translatesAutoresizingMaskIntoConstraints = false
        viewfinderHintLabel.text = "Align the provisioning QR"
        viewfinderHintLabel.font = .preferredFont(forTextStyle: .headline)
        viewfinderHintLabel.textColor = .white
        viewfinderHintLabel.textAlignment = .center
        viewfinderHintLabel.numberOfLines = 2
        cameraPlaceholderView.addSubview(viewfinderHintLabel)
        NSLayoutConstraint.activate([
            viewfinderHintLabel.centerXAnchor.constraint(equalTo: cameraPlaceholderView.centerXAnchor),
            viewfinderHintLabel.bottomAnchor.constraint(equalTo: cameraPlaceholderView.bottomAnchor, constant: -24)
        ])

        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center
        contentStack.addArrangedSubview(bodyLabel)

        pinBoxesStack.axis = .horizontal
        pinBoxesStack.alignment = .fill
        pinBoxesStack.distribution = .fillEqually
        pinBoxesStack.spacing = 8
        contentStack.addArrangedSubview(pinBoxesStack)
        for _ in 0..<6 {
            let container = UIView()
            container.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.45)
            container.layer.cornerRadius = 10
            container.layer.borderWidth = 1
            container.layer.borderColor = UIColor.separator.cgColor
            container.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                container.heightAnchor.constraint(equalToConstant: 44)
            ])

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
            label.textAlignment = .center
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            pinBoxLabels.append(label)
            pinBoxesStack.addArrangedSubview(container)
        }

        pinTextField.borderStyle = .roundedRect
        pinTextField.keyboardType = .numberPad
        pinTextField.textAlignment = .center
        pinTextField.isSecureTextEntry = true
        pinTextField.placeholder = "PIN"
        pinTextField.addTarget(self, action: #selector(pinTextChanged), for: .editingChanged)
        contentStack.addArrangedSubview(pinTextField)

        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        contentStack.addArrangedSubview(statusLabel)

        activityIndicator.hidesWhenStopped = true
        contentStack.addArrangedSubview(activityIndicator)

        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.textColor = .systemRed
        contentStack.addArrangedSubview(errorLabel)

        slotsStack.axis = .vertical
        slotsStack.spacing = 12
        slotsStack.alignment = .fill
        contentStack.addArrangedSubview(slotsStack)

        primaryButton.addTarget(self, action: #selector(primaryActionTapped), for: .touchUpInside)
        primaryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        contentStack.addArrangedSubview(primaryButton)

        secondaryButton.addTarget(self, action: #selector(secondaryActionTapped), for: .touchUpInside)
        secondaryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        contentStack.addArrangedSubview(secondaryButton)

        updatePinUi()
    }

    private func bindBleState() {
        bleService.$isWindowOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isWindowOpen in
                self?.handleWindowOpenChange(isWindowOpen)
            }
            .store(in: &cancellables)

        bleService.$managementState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusText()
            }
            .store(in: &cancellables)

        bleService.$locationAuthorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if self.onboardingState == .locationPermission, status == .authorizedAlways {
                    self.onboardingState = .success
                } else if self.onboardingState == .locationPermission {
                    self.updateUiForState()
                }
            }
            .store(in: &cancellables)
    }

    @objc private func primaryActionTapped() {
        switch onboardingState {
        case .camera:
            startRecoveryFlow()
        case .pin:
            confirmPin()
        case .importing:
            break
        case .recovery:
            if recoveryState == .slotPicker || recoveryState == .ownerProof {
                beginSelectedSlotRecovery()
            } else if recoveryState == .error {
                startRecoveryFlow()
            }
        case .locationPermission:
            requestLocationPermission()
        case .success:
            onProvisioned()
        }
    }

    @objc private func secondaryActionTapped() {
        switch onboardingState {
        case .camera:
            break
        case .pin:
            returnToCamera()
        case .importing:
            break
        case .recovery:
            resetRecoveryFlow()
        case .locationPermission:
            onboardingState = .success
        case .success:
            break
        }
    }

    @objc private func slotButtonTapped(_ sender: UIButton) {
        guard sender.isEnabled else { return }
        selectedSlotId = sender.tag
    }

    @objc private func pinTextChanged() {
        let digits = (pinTextField.text ?? "").filter(\.isNumber)
        let trimmed = String(digits.prefix(6))
        if pinCode != trimmed {
            pinCode = trimmed
        }
        pinErrorMessage = nil
    }

    private func startRecoveryFlow() {
        recoveryTask?.cancel()
        recoveryErrorMessage = nil
        scanErrorMessage = nil
        pinErrorMessage = nil
        recoverySlots = []
        successOverviewSlots = []
        pendingProvisioningMaterial = nil
        selectedSlotId = nil
        importTask?.cancel()
        resetSuccessAnimation()
        onboardingState = .recovery
        recoveryState = .waitingForWindowOpen
        stopCameraSession()
        bleService.stopWindowOpenScan()
        bleService.startWindowOpenScan()
    }

    private func resetRecoveryFlow() {
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryErrorMessage = nil
        recoverySlots = []
        successOverviewSlots = []
        pendingProvisioningMaterial = nil
        selectedSlotId = nil
        importTask?.cancel()
        bleService.stopWindowOpenScan()
        bleService.disconnectManagement()
        onboardingState = .camera
        isScanLocked = false
    }

    private func returnToCamera() {
        pendingEncryptedPayload = nil
        provisioningSuccess = nil
        successOverviewSlots = []
        pendingProvisioningMaterial = nil
        pinCode = ""
        pinErrorMessage = nil
        scanErrorMessage = nil
        isScanLocked = false
        isProvisioningInFlight = false
        importTask?.cancel()
        resetSuccessAnimation()
        onboardingState = .camera
    }

    private func startImportTransition(slotId: Int, key: Data, counter: UInt32, name: String, statusText: String) {
        pendingProvisioningMaterial = PendingProvisioningMaterial(
            slotId: slotId,
            key: key,
            counter: counter,
            name: name,
            statusText: statusText
        )
        importTask?.cancel()
        resetSuccessAnimation()
        onboardingState = .importing
        importTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.onboardingState == .importing,
                      let pending = self.pendingProvisioningMaterial else {
                    return
                }
                self.saveProvisionedMaterial(
                    slotId: pending.slotId,
                    key: pending.key,
                    counter: pending.counter,
                    name: pending.name
                )
            }
        }
    }

    private func requestLocationPermission() {
        switch bleService.locationAuthorizationStatus {
        case .authorizedAlways:
            onboardingState = .success
        case .denied, .restricted:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        default:
            bleService.requestAlwaysLocationAuthorization()
            updateUiForState()
        }
    }

    private func handleWindowOpenChange(_ isWindowOpen: Bool) {
        guard isWindowOpen,
              onboardingState == .recovery,
              recoveryState == .waitingForWindowOpen,
              recoveryTask == nil else {
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        recoveryState = .connecting
        bleService.stopWindowOpenScan()

        recoveryTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.bleService.connectManagement(mode: .windowOpenRecovery)
                await MainActor.run {
                    self.recoveryState = .loadingSlots
                }

                let response = try await self.bleService.requestSlots()

                await MainActor.run {
                    self.recoverySlots = response.slots.sorted { $0.id < $1.id }
                    self.selectedSlotId = self.recoverySlots.first(where: { $0.used })?.id
                    self.recoveryState = .slotPicker
                    self.recoveryTask = nil
                }
            } catch is CancellationError {
                self.bleService.disconnectManagement()
                await MainActor.run {
                    self.recoveryTask = nil
                }
            } catch {
                self.bleService.disconnectManagement()
                await MainActor.run {
                    self.recoveryErrorMessage = error.localizedDescription
                    self.recoveryState = .error
                    self.recoveryTask = nil
                }
            }
        }
    }

    private func beginSelectedSlotRecovery() {
        guard recoveryState == .slotPicker,
              let selectedSlotId,
              let slot = recoverySlots.first(where: { $0.id == selectedSlotId && $0.used }) else {
            if recoveryState == .ownerProof,
               let selectedSlotId,
               let slot = recoverySlots.first(where: { $0.id == selectedSlotId && $0.used }) {
                beginSelectedSlotRecoveryForSlot(slot)
                return
            }
            recoveryErrorMessage = "Select an occupied slot to recover onto this phone."
            return
        }

        beginSelectedSlotRecoveryForSlot(slot)
    }

    private func beginSelectedSlotRecoveryForSlot(_ slot: BleManagementSlot) {
        if slot.id == 1 && recoveryState != .ownerProof {
            recoveryErrorMessage = nil
            recoveryState = .ownerProof
            return
        }

        recoveryErrorMessage = nil
        recoveryState = .recovering
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            guard let self else { return }

            do {
                let recoveryKey = try self.generateRecoveryKey()
                let recoveryName = self.defaultRecoveredSlotName(for: slot)
                let response = try await self.bleService.recover(
                    slotId: slot.id,
                    key: recoveryKey,
                    counter: 0,
                    name: recoveryName
                )
                self.bleService.disconnectManagement()

                await MainActor.run {
                    let finalName = response.name ?? recoveryName
                    let finalCounter = response.counter ?? 0
                    self.recoverySlots = self.buildSuccessOverviewSlots(
                        selectedSlotId: slot.id,
                        counter: finalCounter,
                        name: finalName,
                        knownSlots: self.recoverySlots
                    )
                    self.saveProvisionedMaterial(
                        slotId: slot.id,
                        key: recoveryKey,
                        counter: finalCounter,
                        name: finalName
                    )
                    self.recoveryTask = nil
                }
            } catch is CancellationError {
                self.bleService.disconnectManagement()
                await MainActor.run {
                    self.recoveryTask = nil
                }
            } catch {
                await MainActor.run {
                    if slot.id == 1 && self.isOwnerRecoveryPairingError(error) {
                        self.recoveryErrorMessage = "Pairing failed. Check the 6-digit Guillemot PIN and try again. iOS should show the system Bluetooth pairing prompt for Owner recovery."
                        self.recoveryState = .ownerProof
                    } else {
                        self.bleService.disconnectManagement()
                        self.recoveryErrorMessage = error.localizedDescription
                        self.recoveryState = .error
                    }
                    self.recoveryTask = nil
                }
            }
        }
    }

    private func rebuildSlotsContent() {
        slotsStack.arrangedSubviews.forEach { subview in
            slotsStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        if onboardingState == .recovery && recoveryState == .slotPicker {
            for slot in recoverySlots {
                let button = UIButton(type: .system)
                button.tag = slot.id
                button.contentHorizontalAlignment = .leading
                button.titleLabel?.numberOfLines = 0
                button.titleLabel?.font = .preferredFont(forTextStyle: .body)
                button.layer.cornerRadius = 18
                button.layer.borderWidth = 1
                button.layer.borderColor = UIColor.separator.cgColor
                button.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.35)
                button.configuration = .plain()
                button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
                button.isEnabled = slot.used
                button.alpha = slot.used ? 1.0 : 0.6

                let slotName = slot.used ? (slot.name.isEmpty ? "In use" : slot.name) : "Empty"
                let detail = slot.used ? "Counter \(slot.counter)" : "Available"
                let tier = slotTierLabel(for: slot.id)
                button.setTitle("Slot \(slot.id)\n\(slotName) · \(detail)\n\(tier)", for: .normal)
                button.addTarget(self, action: #selector(slotButtonTapped(_:)), for: .touchUpInside)
                slotsStack.addArrangedSubview(button)
            }
        } else if onboardingState == .success {
            successOverviewSlots.forEach(addSuccessSlotRow)
        }

        updateSlotSelectionUi()
    }

    private func updateSlotSelectionUi() {
        for case let button as UIButton in slotsStack.arrangedSubviews {
            let isSelected = button.tag == selectedSlotId
            button.layer.borderColor = (isSelected ? view.tintColor : UIColor.separator).cgColor
            button.backgroundColor = isSelected
                ? view.tintColor.withAlphaComponent(0.14)
                : UIColor.secondarySystemFill.withAlphaComponent(0.35)
        }
    }

    private func updatePinUi() {
        for (index, label) in pinBoxLabels.enumerated() {
            label.text = index < pinCode.count ? String(pinCode[pinCode.index(pinCode.startIndex, offsetBy: index)]) : ""
        }
        if pinTextField.text != pinCode {
            pinTextField.text = pinCode
        }
        updatePrimaryButtonState()
    }

    private func updatePrimaryButtonState() {
        switch onboardingState {
        case .pin:
            primaryButton.isEnabled = pinCode.count == 6 && !isProvisioningInFlight
        case .importing:
            primaryButton.isEnabled = false
        case .recovery:
            primaryButton.isEnabled = recoveryState == .error || (recoveryState == .slotPicker && selectedSlotId != nil) || recoveryState == .ownerProof
        case .locationPermission, .camera, .success:
            primaryButton.isEnabled = true
        }
    }

    private func updateUiForState() {
        titleLabel.text = "Onboarding"
        successAnimationView.isHidden = true
        pinBoxesStack.isHidden = true
        pinTextField.isHidden = true
        slotsStack.isHidden = true
        errorLabel.isHidden = true
        statusLabel.isHidden = false
        viewfinderHintLabel.isHidden = false

        switch onboardingState {
        case .camera:
            cameraPlaceholderView.isHidden = false
            successAnimationView.isHidden = true
            bodyLabel.text = "Scan from Whimbrel\n\nPoint the camera at an immogen://prov QR code. Guest payloads provision immediately; owner and migration payloads continue to PIN entry."
            statusLabel.text = scanErrorMessage ?? "Scanning for provisioning QR codes..."
            statusLabel.textColor = scanErrorMessage == nil ? .secondaryLabel : .systemRed
            errorLabel.isHidden = true
            activityIndicator.stopAnimating()
            primaryButton.isHidden = false
            primaryButton.setTitle("recover key from lost phone >", for: .normal)
            secondaryButton.isHidden = true
            updateCameraSessionForCurrentState()

        case .pin:
            cameraPlaceholderView.isHidden = true
            successAnimationView.isHidden = true
            bodyLabel.text = "Enter your 6-digit PIN. This is the PIN you set during Guillemot setup."
            pinBoxesStack.isHidden = false
            pinTextField.isHidden = false
            statusLabel.text = nil
            activityIndicator.stopAnimating()
            errorLabel.isHidden = pinErrorMessage == nil
            primaryButton.isHidden = false
            primaryButton.setTitle(isProvisioningInFlight ? "Decrypting..." : "Confirm", for: .normal)
            secondaryButton.isHidden = false
            secondaryButton.setTitle("Back to scan", for: .normal)
            stopCameraSession()

        case .importing:
            cameraPlaceholderView.isHidden = true
            successAnimationView.isHidden = false
            successSymbolLabel.text = "🔑"
            bodyLabel.text = pendingProvisioningMaterial?.statusText ?? "Securing your phone key on this device."
            slotsStack.isHidden = true
            statusLabel.text = ""
            errorLabel.isHidden = true
            activityIndicator.stopAnimating()
            primaryButton.isHidden = true
            secondaryButton.isHidden = true
            playSuccessAnimationIfNeeded()
            stopCameraSession()

        case .recovery:
            cameraPlaceholderView.isHidden = true
            successAnimationView.isHidden = true
            bodyLabel.text = recoveryState == .slotPicker
                ? "Pick the phone slot you want to replace on this device. Pipit will mint a fresh AES key and revoke the lost phone immediately."
                : recoveryState == .ownerProof
                    ? "Recovering Slot 1 requires BLE owner proof. When you continue, iOS should show the system Bluetooth pairing prompt. Enter the 6-digit Guillemot PIN to authorize the recovery."
                    : "Press the button three times on your Uguisu fob. Pipit will detect the Window Open beacon automatically."
            slotsStack.isHidden = recoveryState != .slotPicker
            statusLabel.textColor = recoveryState == .error ? .systemRed : .label
            errorLabel.isHidden = recoveryState != .ownerProof || recoveryErrorMessage == nil
            activityIndicator.isHidden = false
            if recoveryState == .slotPicker || recoveryState == .ownerProof {
                activityIndicator.stopAnimating()
            } else {
                activityIndicator.startAnimating()
            }
            primaryButton.isHidden = !(recoveryState == .error || recoveryState == .slotPicker || recoveryState == .ownerProof)
            primaryButton.setTitle(recoveryState == .slotPicker ? "Recover this slot" : recoveryState == .ownerProof ? "Continue to pairing" : "Try again", for: .normal)
            secondaryButton.isHidden = false
            secondaryButton.setTitle("Back to scan", for: .normal)
            stopCameraSession()

        case .locationPermission:
            cameraPlaceholderView.isHidden = true
            successAnimationView.isHidden = true
            bodyLabel.text = "Enable proximity unlock?\n\nPipit can automatically unlock your vehicle when you walk up to it. This requires Always Allow location access so the app can detect your vehicle in the background. Your location is never stored or transmitted."
            slotsStack.isHidden = true
            statusLabel.text = locationPermissionStatusText()
            statusLabel.textColor = .secondaryLabel
            errorLabel.isHidden = true
            activityIndicator.stopAnimating()
            primaryButton.isHidden = false
            primaryButton.setTitle(bleService.locationAuthorizationStatus == .denied || bleService.locationAuthorizationStatus == .restricted ? "Open Settings" : "Enable Proximity", for: .normal)
            secondaryButton.isHidden = false
            secondaryButton.setTitle("Skip for Now", for: .normal)
            stopCameraSession()

        case .success:
            titleLabel.text = "You're all set."
            successAnimationView.isHidden = true
            cameraPlaceholderView.isHidden = true
            bodyLabel.text = "The key has been stored in the secure keystore on this device."
            slotsStack.isHidden = false
            statusLabel.textColor = .label
            statusLabel.text = nil
            activityIndicator.stopAnimating()
            primaryButton.isHidden = false
            primaryButton.setTitle("Continue", for: .normal)
            secondaryButton.isHidden = true
            rebuildSlotsContent()
            stopCameraSession()
        }

        updateStatusText()
        updatePrimaryButtonState()
    }

    private func updateStatusText() {
        switch onboardingState {
        case .camera:
            statusLabel.text = scanErrorMessage ?? "Scanning for provisioning QR codes..."
            statusLabel.textColor = scanErrorMessage == nil ? .secondaryLabel : .systemRed

        case .pin:
            statusLabel.text = nil
            statusLabel.textColor = .label

        case .importing:
            statusLabel.text = nil
            statusLabel.textColor = .label

        case .recovery:
            switch recoveryState {
            case .waitingForWindowOpen:
                statusLabel.text = "Scanning for the Window Open beacon..."
            case .connecting:
                statusLabel.text = managementStatusText()
            case .loadingSlots:
                statusLabel.text = "Management session ready. Loading slots..."
            case .ownerProof:
                statusLabel.text = "The next step uses iOS's Bluetooth pairing prompt for Owner recovery."
            case .recovering:
                statusLabel.text = selectedSlotId.map { "Recovering slot \($0) onto this phone..." } ?? "Recovering the selected slot..."
            case .slotPicker:
                statusLabel.text = selectedSlotId.map { "Selected slot \($0)" } ?? "Select a slot to recover onto this phone."
            case .error:
                statusLabel.text = recoveryErrorMessage
            }
            statusLabel.textColor = recoveryState == .error ? .systemRed : .label

        case .locationPermission:
            statusLabel.text = locationPermissionStatusText()
            statusLabel.textColor = .secondaryLabel

        case .success:
            statusLabel.text = nil
            statusLabel.textColor = .label
        }
    }

    private func updateCameraSessionForCurrentState() {
        if onboardingState == .camera {
            requestCameraAccessIfNeededAndStart()
        } else {
            stopCameraSession()
        }
    }

    private func requestCameraAccessIfNeededAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            scanErrorMessage = nil
            startCameraSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.scanErrorMessage = nil
                        self.startCameraSession()
                    } else {
                        self.scanErrorMessage = "Camera permission is required to scan Whimbrel QR codes."
                        self.updateUiForState()
                    }
                }
            }
        case .denied, .restricted:
            scanErrorMessage = "Camera permission is required to scan Whimbrel QR codes."
            updateUiForState()
        @unknown default:
            scanErrorMessage = "Camera permission is unavailable on this device."
            updateUiForState()
        }
    }

    private func startCameraSession() {
        guard onboardingState == .camera else { return }

        do {
            try configureCameraSessionIfNeeded()
        } catch {
            scanErrorMessage = error.localizedDescription
            updateUiForState()
            return
        }

        cameraQueue.async { [weak self] in
            guard let self, let session = self.captureSession, !session.isRunning else { return }
            session.startRunning()
        }
    }

    private func stopCameraSession() {
        cameraQueue.async { [weak self] in
            guard let self, let session = self.captureSession, session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func configureCameraSessionIfNeeded() throws {
        if captureSession != nil {
            return
        }

        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            throw IosBleProximityServiceError.system("No camera is available on this device")
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
        guard session.canAddInput(deviceInput) else {
            throw IosBleProximityServiceError.system("Unable to configure camera input")
        }
        session.addInput(deviceInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            throw IosBleProximityServiceError.system("Unable to configure QR metadata output")
        }
        session.addOutput(metadataOutput)
        metadataOutput.metadataObjectTypes = [.qr]
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)

        session.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = cameraPlaceholderView.bounds
        cameraPlaceholderView.layer.insertSublayer(previewLayer, at: 0)

        self.captureSession = session
        self.previewLayer = previewLayer
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard onboardingState == .camera, !isScanLocked else { return }
        guard let qrObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let rawValue = qrObject.stringValue else {
            return
        }
        handleScannedQr(rawValue)
    }

    private func handleScannedQr(_ rawValue: String) {
        guard onboardingState == .camera, !isScanLocked else { return }

        let payload: ParsedProvisioningPayload
        do {
            guard let parsedPayload = try parseProvisioningQrIfNeeded(rawValue) else {
                return
            }
            payload = parsedPayload
        } catch {
            scanErrorMessage = error.localizedDescription
            updateUiForState()
            return
        }

        scanErrorMessage = nil
        isScanLocked = true
        stopCameraSession()

        switch payload {
        case .guest(let slotId, let key, let counter, let name):
            startImportTransition(
                slotId: slotId,
                key: key,
                counter: counter,
                name: name,
                statusText: "Importing your phone key..."
            )

        case .encrypted:
            pendingEncryptedPayload = payload
            pinCode = ""
            pinErrorMessage = nil
            isScanLocked = false
            onboardingState = .pin
            pinTextField.becomeFirstResponder()
        }
    }

    private func confirmPin() {
        guard case let .encrypted(slotId, salt, encryptedKey, counter, name)? = pendingEncryptedPayload else {
            return
        }
        guard pinCode.count == 6, !isProvisioningInFlight else {
            return
        }

        pinErrorMessage = nil
        isProvisioningInFlight = true

        Task { [weak self] in
            guard let self else { return }

            do {
#if canImport(shared)
                try await self.ensureCryptoInitialized()
                let decryptedKey = try await self.decryptProvisionedKey(
                    pin: self.pinCode,
                    salt: salt,
                    encryptedKey: encryptedKey
                )
                await MainActor.run {
                    self.startImportTransition(
                        slotId: slotId,
                        key: decryptedKey,
                        counter: counter,
                        name: name,
                        statusText: "Decrypting and securing your phone key..."
                    )
                }
#else
                throw IosBleProximityServiceError.unsupported("Shared framework is unavailable for QR decryption")
#endif
            } catch {
                await MainActor.run {
                    self.pinErrorMessage = error.localizedDescription.contains("Invalid PIN")
                        ? "Incorrect PIN."
                        : error.localizedDescription
                    self.errorLabel.isHidden = false
                }
            }

            await MainActor.run {
                self.isProvisioningInFlight = false
            }
        }
    }

    private func saveProvisionedMaterial(slotId: Int, key: Data, counter: UInt32, name: String) {
#if canImport(shared)
        pendingProvisioningMaterial = nil
        importTask?.cancel()
        keyStore.saveKey(slotId: Int32(slotId), key: kotlinByteArray(from: Array(key)))
        keyStore.saveCounter(slotId: Int32(slotId), counter: counter)
        provisioningSuccess = ProvisioningSuccess(slotId: slotId, counter: counter, name: name)
        successOverviewSlots = buildSuccessOverviewSlots(
            selectedSlotId: slotId,
            counter: counter,
            name: name,
            knownSlots: recoverySlots
        )
        pinCode = ""
        pendingEncryptedPayload = nil
        scanErrorMessage = nil
        pinErrorMessage = nil
        isScanLocked = false
        onboardingState = bleService.hasAlwaysLocationAuthorization ? .success : .locationPermission
#else
        scanErrorMessage = "Shared framework is unavailable for secure provisioning"
        onboardingState = .camera
#endif
    }

    private func addSuccessSlotRow(_ slot: BleManagementSlot) {
        let isCurrentPhone = slot.id == provisioningSuccess?.slotId

        let container = UIView()
        container.backgroundColor = isCurrentPhone
            ? view.tintColor.withAlphaComponent(0.12)
            : UIColor.secondarySystemFill.withAlphaComponent(0.35)
        container.layer.cornerRadius = 18
        container.layer.borderWidth = 1
        container.layer.borderColor = (isCurrentPhone ? view.tintColor : UIColor.separator).cgColor

        let horizontalStack = UIStackView()
        horizontalStack.axis = .horizontal
        horizontalStack.alignment = .top
        horizontalStack.spacing = 12
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(horizontalStack)

        let leftStack = UIStackView()
        leftStack.axis = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 4

        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .headline)
        title.text = "Slot \(slot.id)"

        let nameLabel = UILabel()
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.text = slot.name.isEmpty ? "Empty" : slot.name
        nameLabel.numberOfLines = 0

        let tierLabel = UILabel()
        tierLabel.font = .preferredFont(forTextStyle: .caption1)
        tierLabel.textColor = .secondaryLabel
        tierLabel.text = slotTierLabel(for: slot.id)

        leftStack.addArrangedSubview(title)
        leftStack.addArrangedSubview(nameLabel)
        leftStack.addArrangedSubview(tierLabel)

        let rightStack = UIStackView()
        rightStack.axis = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 4

        let stateLabel = UILabel()
        stateLabel.font = .preferredFont(forTextStyle: .caption1)
        stateLabel.textColor = slot.used || slot.id == 0 ? view.tintColor : .secondaryLabel
        stateLabel.text = {
            if slot.id == 0 { return "KEY" }
            if isCurrentPhone { return "THIS PHONE" }
            return slot.used ? "ACTIVE" : "EMPTY"
        }()

        let counterLabel = UILabel()
        counterLabel.font = .preferredFont(forTextStyle: .caption1)
        counterLabel.textColor = .secondaryLabel
        counterLabel.text = slot.id == 0 ? "Hardware fob" : "Counter \(slot.counter)"

        rightStack.addArrangedSubview(stateLabel)
        rightStack.addArrangedSubview(counterLabel)

        horizontalStack.addArrangedSubview(leftStack)
        horizontalStack.addArrangedSubview(rightStack)

        NSLayoutConstraint.activate([
            horizontalStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            horizontalStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            horizontalStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            horizontalStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])

        slotsStack.addArrangedSubview(container)
    }

    private func buildSuccessOverviewSlots(
        selectedSlotId: Int,
        counter: UInt32,
        name: String,
        knownSlots: [BleManagementSlot]
    ) -> [BleManagementSlot] {
        (0...3).map { slotId in
            if slotId == 0 {
                return BleManagementSlot(id: 0, used: true, counter: 0, name: "Uguisu")
            }
            if slotId == selectedSlotId {
                return BleManagementSlot(id: slotId, used: true, counter: counter, name: name)
            }
            return knownSlots.first(where: { $0.id == slotId })
                ?? BleManagementSlot(id: slotId, used: false, counter: 0, name: "")
        }
    }

    private func slotTierLabel(for slotId: Int) -> String {
        switch slotId {
        case 0:
            return "HARDWARE KEY"
        case 1:
            return "OWNER"
        case 2, 3:
            return "GUEST"
        default:
            return "PHONE SLOT"
        }
    }

    private func defaultRecoveredSlotName(for slot: BleManagementSlot) -> String {
        if !slot.name.isEmpty {
            return slot.name
        }

        switch slot.id {
        case 1:
            return "Recovered owner phone"
        case 2, 3:
            return "Recovered guest phone"
        default:
            return "Recovered phone"
        }
    }

    private func locationPermissionStatusText() -> String {
        switch bleService.locationAuthorizationStatus {
        case .authorizedAlways:
            return "Always Allow is already enabled."
        case .authorizedWhenInUse:
            return "When In Use is enabled. Upgrade to Always Allow to keep proximity unlock active in the background."
        case .notDetermined:
            return "Enable Proximity triggers the iOS Always Allow prompt."
        case .denied, .restricted:
            return "Location access is currently disabled. Open Settings to enable Always Allow later, or skip for now and use Pipit as a manual key fob."
        @unknown default:
            return "Location permission status is unavailable on this device."
        }
    }

    private func resetSuccessAnimation() {
        hasPlayedSuccessAnimation = false
        successAnimationView.layer.removeAllAnimations()
        successParticles.forEach { particle in
            particle.layer.removeAllAnimations()
            particle.removeFromSuperview()
        }
        successParticles.removeAll()
        successSymbolLabel.layer.removeAllAnimations()
        successSymbolLabel.alpha = 0
        successSymbolLabel.text = "🔑"
        successSymbolLabel.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
    }

    private func playSuccessAnimationIfNeeded() {
        guard !hasPlayedSuccessAnimation else { return }
        hasPlayedSuccessAnimation = true

        resetSuccessAnimation()
        hasPlayedSuccessAnimation = true
        view.layoutIfNeeded()

        let baseOffsets: [CGPoint] = [
            CGPoint(x: -72, y: -46), CGPoint(x: -40, y: -72), CGPoint(x: 16, y: -78),
            CGPoint(x: 64, y: -38), CGPoint(x: 74, y: 6), CGPoint(x: 48, y: 62),
            CGPoint(x: -6, y: 78), CGPoint(x: -58, y: 52), CGPoint(x: -78, y: 8),
            CGPoint(x: -18, y: -24), CGPoint(x: 28, y: -10), CGPoint(x: 8, y: 34)
        ]

        for (index, offset) in baseOffsets.enumerated() {
            let particle = UIView(frame: CGRect(x: 0, y: 0, width: index % 3 == 0 ? 12 : 9, height: index % 3 == 0 ? 12 : 9))
            particle.backgroundColor = UIColor.label.withAlphaComponent(0.9)
            particle.layer.cornerRadius = 2
            successAnimationView.addSubview(particle)
            successParticles.append(particle)
            particle.center = CGPoint(x: successAnimationView.bounds.midX, y: successAnimationView.bounds.midY)

            UIView.animate(
                withDuration: 0.36,
                delay: Double(index) * 0.012,
                options: [.curveEaseOut],
                animations: {
                    particle.center = CGPoint(
                        x: self.successAnimationView.bounds.midX + offset.x,
                        y: self.successAnimationView.bounds.midY + offset.y
                    )
                    particle.transform = CGAffineTransform(rotationAngle: CGFloat(index.isMultiple(of: 2) ? 0.6 : -0.6))
                }
            ) { _ in
                UIView.animate(
                    withDuration: 0.34,
                    delay: 0.0,
                    options: [.curveEaseInOut],
                    animations: {
                        particle.center = CGPoint(x: self.successAnimationView.bounds.midX, y: self.successAnimationView.bounds.midY)
                        particle.transform = .identity
                        particle.backgroundColor = self.view.tintColor
                    }
                ) { _ in
                    UIView.animate(
                        withDuration: 0.18,
                        delay: 0.0,
                        options: [.curveEaseIn],
                        animations: {
                            particle.alpha = 0
                            particle.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                        }
                    )
                }
            }
        }

        UIView.animate(
            withDuration: 0.22,
            delay: 0.76,
            options: [.curveEaseOut],
            animations: {
                self.successSymbolLabel.alpha = 1
                self.successSymbolLabel.transform = .identity
            }
        ) { _ in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func layoutSuccessParticlesAtCenter() {
        let center = CGPoint(x: successAnimationView.bounds.midX, y: successAnimationView.bounds.midY)
        successParticles.filter { $0.layer.animationKeys()?.isEmpty ?? true }.forEach { particle in
            particle.center = center
        }
    }

    private func isOwnerRecoveryPairingError(_ error: Error) -> Bool {
        if let managementError = error as? BleManagementErrorResponse {
            let code = managementError.code?.lowercased() ?? ""
            let message = managementError.message?.lowercased() ?? ""
            return code == "locked" || message.contains("pairing") || message.contains("authentication")
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("pairing") || message.contains("authentication") || message.contains("locked")
    }

    private func managementStatusText() -> String {
        switch bleService.managementState.connectionState {
        case .disconnected, .scanning:
            return "Window Open detected. Starting management connection..."
        case .connecting:
            return "Connecting to Guillemot over recovery GATT..."
        case .discovering:
            return "Enabling management characteristics..."
        case .ready:
            return "Management session ready. Fetching slots..."
        case .error:
            return bleService.managementState.lastError ?? "Management session failed."
        }
    }

    private func parseProvisioningQrIfNeeded(_ rawValue: String) throws -> ParsedProvisioningPayload? {
        let prefix = "immogen://prov?"
        guard rawValue.hasPrefix(prefix) else {
            return nil
        }

        let query = String(rawValue.dropFirst(prefix.count))
        let params = try parseQuery(query)
        let slotId = try parseSlotId(params["slot"])
        let counter = try parseCounter(params["ctr"])
        let name = params["name"] ?? ""

        if let keyHex = params["key"], params["salt"] == nil, params["ekey"] == nil {
            return .guest(
                slotId: slotId,
                key: try parseHex(field: "key", value: keyHex, expectedLength: 16),
                counter: counter,
                name: name
            )
        }

        if let saltHex = params["salt"], let encryptedKeyHex = params["ekey"], params["key"] == nil {
            return .encrypted(
                slotId: slotId,
                salt: try parseHex(field: "salt", value: saltHex, expectedLength: 16),
                encryptedKey: try parseHex(field: "ekey", value: encryptedKeyHex, expectedLength: 24),
                counter: counter,
                name: name
            )
        }

        if params["key"] != nil {
            throw ProvisioningQrParseError.unsupportedVariant("Provisioning QR cannot mix guest and encrypted owner fields")
        }

        throw ProvisioningQrParseError.unsupportedVariant("Provisioning QR must contain either key or salt+ekey fields")
    }

    private func parseQuery(_ query: String) throws -> [String: String] {
        guard !query.isEmpty else { return [:] }
        var result: [String: String] = [:]

        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = try percentDecode(String(components[0]))
            let value = try percentDecode(components.count > 1 ? String(components[1]) : "")
            result[key] = value
        }

        return result
    }

    private func percentDecode(_ value: String) throws -> String {
        if let decoded = value.removingPercentEncoding {
            return decoded.replacingOccurrences(of: "+", with: " ")
        }
        throw ProvisioningQrParseError.invalidField("query", "invalid percent escape")
    }

    private func parseSlotId(_ raw: String?) throws -> Int {
        guard let raw else { throw ProvisioningQrParseError.missingField("slot") }
        guard let slotId = Int(raw), (0...3).contains(slotId) else {
            throw ProvisioningQrParseError.invalidField("slot", "must be between 0 and 3")
        }
        return slotId
    }

    private func parseCounter(_ raw: String?) throws -> UInt32 {
        guard let raw else { throw ProvisioningQrParseError.missingField("ctr") }
        guard let counter = UInt32(raw) else {
            throw ProvisioningQrParseError.invalidField("ctr", "expected unsigned integer")
        }
        return counter
    }

    private func parseHex(field: String, value: String, expectedLength: Int) throws -> Data {
        guard value.count == expectedLength * 2 else {
            throw ProvisioningQrParseError.invalidField(field, "expected \(expectedLength) bytes but was \(value.count / 2)")
        }

        var bytes = Data(capacity: expectedLength)
        var index = value.startIndex
        for _ in 0..<expectedLength {
            let nextIndex = value.index(index, offsetBy: 2)
            let byteString = value[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw ProvisioningQrParseError.invalidField(field, "expected hex string")
            }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }

    private func generateRecoveryKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw IosBleProximityServiceError.system("Unable to generate a secure recovery key")
        }
        return Data(bytes)
    }

#if canImport(shared)
    private func ensureCryptoInitialized() async throws {
        if ImmoCrypto.shared.isInitialized() {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ImmoCrypto.shared.initialize { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func decryptProvisionedKey(pin: String, salt: Data, encryptedKey: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            ImmoCrypto.shared.decryptProvisionedKeyAsync(
                pin: pin,
                salt: kotlinByteArray(from: Array(salt)),
                encryptedKey: kotlinByteArray(from: Array(encryptedKey)),
                params: defaultArgonParams()
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: self.data(from: result))
                } else {
                    continuation.resume(throwing: IosBleProximityServiceError.system("Provisioning decrypt returned no result"))
                }
            }
        }
    }

    private func defaultArgonParams() -> ImmoCrypto.Argon2Params {
        ImmoCrypto.Argon2Params(
            parallelism: 1,
            outputLength: UInt32(ImmoCrypto.shared.QR_KEY_LEN),
            requestedMemoryKiB: 262_144,
            iterations: 3,
            key: kotlinByteArray(from: []),
            associatedData: kotlinByteArray(from: []),
            variant: ImmoCrypto.ArgonVariant.argon2id
        )
    }

    private func kotlinByteArray(from bytes: [UInt8]) -> KotlinByteArray {
        let array = KotlinByteArray(size: Int32(bytes.count))
        for (index, value) in bytes.enumerated() {
            array.set(index: Int32(index), value: Int8(bitPattern: value))
        }
        return array
    }

    private func data(from array: KotlinByteArray) -> Data {
        Data((0..<Int(array.size)).map { UInt8(bitPattern: array.get(index: Int32($0))) })
    }
#endif
}
