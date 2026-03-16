import UIKit
import Combine
import CoreImage
import Security

#if canImport(shared)
import shared
#endif

@MainActor
final class SettingsPlaceholderViewController: UIViewController {

    private enum SlotLoadState {
        case idle
        case loading
        case loaded
        case error(String)
    }

    private let bleService: IosBleProximityService
    private let onLocalKeyDeleted: () -> Void
    private let onClose: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var slotLoadTask: Task<Void, Never>?
    private var slotLoadState: SlotLoadState = .idle {
        didSet {
            updateStatusUi()
            rebuildDynamicContent()
        }
    }
    private var loadedSlots: [BleManagementSlot] = [] {
        didSet { rebuildDynamicContent() }
    }

#if canImport(shared)
    private let keyStore = KeyStoreManager()
    private let appSettings = AppSettings(manager: IosSettingsManager(userDefaults: UserDefaults.standard))
#endif

    private lazy var localSlotId: Int? = resolveLocalPhoneSlotId()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let headerStack = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let statusRow = UIStackView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let errorLabel = UILabel()

    private let proximitySectionBody = UIStackView()
    private let proximityToggleRow = UIStackView()
    private let proximityTitleLabel = UILabel()
    private let proximitySubtitleLabel = UILabel()
    private let proximitySwitch = UISwitch()
    private let unlockSlider = UISlider()
    private let unlockValueLabel = UILabel()
    private let lockSlider = UISlider()
    private let lockValueLabel = UILabel()

    private let keysSectionContainer = UIView()
    private let keysSectionBody = UIStackView()
    private let yourKeySectionContainer = UIView()
    private let yourKeySectionBody = UIStackView()
    private let deviceSectionContainer = UIView()
    private let deviceSectionBody = UIStackView()
    private let aboutSectionBody = UIStackView()
    private let qrContext = CIContext()

    init(bleService: IosBleProximityService, onLocalKeyDeleted: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.bleService = bleService
        self.onLocalKeyDeleted = onLocalKeyDeleted
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        slotLoadTask?.cancel()
        bleService.disconnectManagement()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        configureLayout()
        configureProximityControls()
        bindBleState()
        loadStoredProximitySettings()
        updateHeaderCopy()
        updateStatusUi()
        rebuildDynamicContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if case .idle = slotLoadState {
            loadSlots()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        bleService.disconnectManagement()
    }

    private var isOwnerView: Bool {
        localSlotId == 1
    }

    private var completedSlots: [BleManagementSlot] {
        var slotsById: [Int: BleManagementSlot] = [:]
        for slot in loadedSlots {
            if slotsById[slot.id] == nil {
                slotsById[slot.id] = slot
            }
        }
        return (0...3).map { slotId in
            slotsById[slotId] ?? BleManagementSlot(
                id: slotId,
                used: false,
                counter: 0,
                name: slotId == 0 ? "Uguisu" : ""
            )
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

        headerStack.axis = .horizontal
        headerStack.alignment = .top
        headerStack.spacing = 12

        let titleStack = UIStackView()
        titleStack.axis = .vertical
        titleStack.spacing = 4

        titleLabel.font = .preferredFont(forTextStyle: .title1)
        titleLabel.text = "Settings"

        subtitleLabel.numberOfLines = 0
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel

        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(subtitleLabel)

        closeButton.setTitle("Close", for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        headerStack.addArrangedSubview(titleStack)
        headerStack.addArrangedSubview(closeButton)
        titleStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(headerStack)

        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 10

        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabel

        retryButton.setTitle("Retry", for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        statusRow.addArrangedSubview(activityIndicator)
        statusRow.addArrangedSubview(statusLabel)
        statusRow.addArrangedSubview(retryButton)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        retryButton.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(statusRow)

        errorLabel.numberOfLines = 0
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        contentStack.addArrangedSubview(errorLabel)

        configureSectionBody(proximitySectionBody)
        configureSectionBody(proximityToggleRow)
        contentStack.addArrangedSubview(makeSectionView(
            title: "PROXIMITY",
            subtitle: "These preferences are stored locally and already feed the existing BLE proximity layer.",
            body: proximitySectionBody
        ))

        configureSectionBody(keysSectionBody)
        contentStack.addArrangedSubview(makeSectionView(
            title: "KEYS",
            subtitle: "Live slot data comes from SLOTS? over the existing management transport. Owner writes re-identify before mutating a slot.",
            body: keysSectionBody,
            container: keysSectionContainer
        ))

        configureSectionBody(yourKeySectionBody)
        contentStack.addArrangedSubview(makeSectionView(
            title: "YOUR KEY",
            subtitle: "Your phone slot stays separate from the rest of the vehicle state and owns its transfer flow.",
            body: yourKeySectionBody,
            container: yourKeySectionContainer
        ))

        configureSectionBody(deviceSectionBody)
        contentStack.addArrangedSubview(makeSectionView(
            title: "DEVICE",
            subtitle: "Owner migration stays here. USB-C OTG maintenance remains Android-only and is intentionally hidden on iOS.",
            body: deviceSectionBody,
            container: deviceSectionContainer
        ))

        configureSectionBody(aboutSectionBody)
        contentStack.addArrangedSubview(makeSectionView(
            title: "ABOUT",
            subtitle: "Management session state and slot context.",
            body: aboutSectionBody
        ))
    }

    private func configureProximityControls() {
        proximityToggleRow.axis = .horizontal
        proximityToggleRow.alignment = .center
        proximityToggleRow.spacing = 12

        let toggleTextStack = UIStackView()
        toggleTextStack.axis = .vertical
        toggleTextStack.spacing = 4

        proximityTitleLabel.font = .preferredFont(forTextStyle: .headline)
        proximityTitleLabel.text = "Background Unlock"

        proximitySubtitleLabel.numberOfLines = 0
        proximitySubtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        proximitySubtitleLabel.textColor = .secondaryLabel

        toggleTextStack.addArrangedSubview(proximityTitleLabel)
        toggleTextStack.addArrangedSubview(proximitySubtitleLabel)
        proximityToggleRow.addArrangedSubview(toggleTextStack)
        proximityToggleRow.addArrangedSubview(proximitySwitch)
        toggleTextStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        proximitySwitch.setContentHuggingPriority(.required, for: .horizontal)

        proximitySwitch.addTarget(self, action: #selector(backgroundUnlockChanged), for: .valueChanged)

        proximitySectionBody.addArrangedSubview(proximityToggleRow)
        proximitySectionBody.addArrangedSubview(makeSliderBlock(
            title: "Unlock RSSI",
            subtitle: "Closer to 0 unlocks sooner.",
            slider: unlockSlider,
            valueLabel: unlockValueLabel,
            action: #selector(unlockSliderChanged)
        ))
        proximitySectionBody.addArrangedSubview(makeSliderBlock(
            title: "Lock RSSI",
            subtitle: "Always at least 10 dBm weaker than unlock.",
            slider: lockSlider,
            valueLabel: lockValueLabel,
            action: #selector(lockSliderChanged)
        ))
    }

    private func bindBleState() {
        bleService.$managementState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusUi()
            }
            .store(in: &cancellables)
    }

    private func loadStoredProximitySettings() {
#if canImport(shared)
        proximitySwitch.isOn = appSettings.isProximityEnabled
        unlockSlider.minimumValue = -95
        unlockSlider.maximumValue = -35
        lockSlider.minimumValue = -105
        lockSlider.maximumValue = Float(appSettings.unlockRssi - 10)
        unlockSlider.value = Float(appSettings.unlockRssi)
        lockSlider.value = Float(appSettings.lockRssi)
        updateProximityUi()
#endif
    }

    private func updateHeaderCopy() {
        switch localSlotId {
        case 1:
            subtitleLabel.text = "Owner controls, guest slot management, transfer QR export, and persisted proximity preferences."
        case 2, 3:
            subtitleLabel.text = "Guest controls, transfer QR export, and a read-only slot overview."
        default:
            subtitleLabel.text = "Read-only settings until a local phone key is available."
        }
    }

    private func updateStatusUi() {
        let managementState = bleService.managementState
        let statusText: String
        let showRetry: Bool

        switch slotLoadState {
        case .idle:
            statusText = "Opening a fresh management session when Settings appears."
            showRetry = false
            activityIndicator.stopAnimating()
            errorLabel.isHidden = true
        case .loading:
            statusText = managementStatusText(for: managementState)
            showRetry = false
            activityIndicator.startAnimating()
            errorLabel.isHidden = true
        case .loaded:
            statusText = "Loaded \(completedSlots.count) slots over the management transport."
            showRetry = false
            activityIndicator.stopAnimating()
            errorLabel.isHidden = true
        case .error(let message):
            statusText = managementStatusText(for: managementState)
            showRetry = true
            activityIndicator.stopAnimating()
            errorLabel.text = message
            errorLabel.isHidden = false
        }

        statusLabel.text = statusText
        retryButton.isHidden = !showRetry
    }

    private func rebuildDynamicContent() {
        keysSectionContainer.isHidden = !isOwnerView
        deviceSectionContainer.isHidden = !isOwnerView
        yourKeySectionContainer.isHidden = isOwnerView

        rebuildKeysSection()
        rebuildYourKeySection()
        rebuildDeviceSection()
        rebuildAboutSection()
    }

    private func rebuildKeysSection() {
        keysSectionBody.removeAllArrangedSubviews()

        switch slotLoadState {
        case .idle:
            keysSectionBody.addArrangedSubview(makeBodyLabel("Waiting to connect to the vehicle."))
        case .loading:
            keysSectionBody.addArrangedSubview(makeBodyLabel(managementStatusText(for: bleService.managementState)))
        case .error(let message):
            keysSectionBody.addArrangedSubview(makeErrorLabel(message))
        case .loaded:
            if completedSlots.isEmpty {
                keysSectionBody.addArrangedSubview(makeBodyLabel("No slots were returned by the vehicle."))
            } else {
                completedSlots.forEach { keysSectionBody.addArrangedSubview(makeOwnerSlotRow(for: $0)) }
            }
        }
    }

    private func rebuildYourKeySection() {
        yourKeySectionBody.removeAllArrangedSubviews()

        if let localSlotId,
           let slot = completedSlots.first(where: { $0.id == localSlotId }) {
            yourKeySectionBody.addArrangedSubview(makeSlotRow(for: slot))
            yourKeySectionBody.addArrangedSubview(makeActionButton(title: "Transfer to New Phone", filled: true) { [weak self] in
                self?.presentTransferConfirmation()
            })
            return
        }

        switch slotLoadState {
        case .loading:
            yourKeySectionBody.addArrangedSubview(makeBodyLabel(managementStatusText(for: bleService.managementState)))
        case .error(let message):
            yourKeySectionBody.addArrangedSubview(makeErrorLabel(message))
        case .loaded:
            yourKeySectionBody.addArrangedSubview(makeBodyLabel("Your local phone key could not be matched to a returned slot."))
        case .idle:
            yourKeySectionBody.addArrangedSubview(makeBodyLabel("Waiting to connect to the vehicle."))
        }
    }

    private func rebuildDeviceSection() {
        deviceSectionBody.removeAllArrangedSubviews()
        deviceSectionBody.addArrangedSubview(makeActionButton(title: "Transfer to New Phone", filled: true) { [weak self] in
            self?.presentTransferConfirmation()
        })
        deviceSectionBody.addArrangedSubview(makeBodyLabel("Slot 0 stays read-only on iOS. Use Whimbrel or Android USB OTG flows for Uguisu replacement, PIN changes, and firmware flashing."))
        deviceSectionBody.addArrangedSubview(makeSecondaryLabel("Current management state: \(managementStatusText(for: bleService.managementState))"))
    }

    private func rebuildAboutSection() {
        aboutSectionBody.removeAllArrangedSubviews()

        if let localSlotId {
            aboutSectionBody.addArrangedSubview(makeBodyLabel("Local phone slot: \(localSlotId)"))
        } else {
            aboutSectionBody.addArrangedSubview(makeBodyLabel("No local phone slot is currently stored on this device."))
        }

        aboutSectionBody.addArrangedSubview(makeSecondaryLabel("Management state: \(managementStatusText(for: bleService.managementState))"))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        aboutSectionBody.addArrangedSubview(makeSecondaryLabel("Version \(version) (\(build))"))

        if !isOwnerView {
            switch slotLoadState {
            case .loaded:
                completedSlots.forEach { aboutSectionBody.addArrangedSubview(makeSlotRow(for: $0)) }
            case .loading:
                aboutSectionBody.addArrangedSubview(makeBodyLabel("Loading the read-only slot overview."))
            case .error(let message):
                aboutSectionBody.addArrangedSubview(makeErrorLabel(message))
            case .idle:
                aboutSectionBody.addArrangedSubview(makeBodyLabel("The slot overview appears here after the first management connection."))
            }
        }
    }

    private func loadSlots() {
        slotLoadTask?.cancel()
        slotLoadState = .loading
        loadedSlots = []

        slotLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await bleService.connectManagement(mode: .standard)
                let response = try await bleService.requestSlots()
                try Task.checkCancellation()
                loadedSlots = response.slots.sorted { $0.id < $1.id }
                slotLoadState = .loaded
            } catch is CancellationError {
                bleService.disconnectManagement()
            } catch {
                bleService.disconnectManagement()
                slotLoadState = .error(error.localizedDescription)
            }
        }
    }

    private func updateProximityUi() {
#if canImport(shared)
        let unlockRssi = Int(appSettings.unlockRssi)
        let lockRssi = Int(appSettings.lockRssi)

        proximitySubtitleLabel.text = proximitySwitch.isOn
            ? "Automatic unlock and lock are enabled."
            : "Manual control only."

        unlockSlider.isEnabled = proximitySwitch.isOn
        lockSlider.isEnabled = proximitySwitch.isOn
        lockSlider.maximumValue = Float(unlockRssi - 10)

        unlockSlider.value = Float(unlockRssi)
        lockSlider.value = Float(lockRssi)
        unlockValueLabel.text = "\(unlockRssi) dBm"
        lockValueLabel.text = "\(lockRssi) dBm"
#endif
    }

    private func makeSectionView(
        title: String,
        subtitle: String,
        body: UIStackView,
        container: UIView? = nil
    ) -> UIView {
        let sectionContainer = container ?? UIView()
        sectionContainer.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.35)
        sectionContainer.layer.cornerRadius = 20

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        sectionContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: sectionContainer.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: sectionContainer.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: sectionContainer.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: sectionContainer.bottomAnchor, constant: -20)
        ])

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
            weight: .semibold
        )
        titleLabel.textColor = view.tintColor
        titleLabel.text = title

        let subtitleLabel = UILabel()
        subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = subtitle

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.addArrangedSubview(body)
        return sectionContainer
    }

    private func makeSliderBlock(
        title: String,
        subtitle: String,
        slider: UISlider,
        valueLabel: UILabel,
        action: Selector
    ) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6

        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 12

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.text = title

        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right

        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(valueLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = subtitle

        slider.addTarget(self, action: action, for: .valueChanged)

        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(subtitleLabel)
        stack.addArrangedSubview(slider)
        return stack
    }

    private func configureSectionBody(_ stack: UIStackView) {
        stack.axis = .vertical
        stack.spacing = 12
    }

    private func makeOwnerSlotRow(for slot: BleManagementSlot) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 16

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        let topRow = UIStackView()
        topRow.axis = .horizontal
        topRow.alignment = .top
        topRow.spacing = 12

        let titleStack = UIStackView()
        titleStack.axis = .vertical
        titleStack.spacing = 4

        let titleLabel = UILabel()
        titleLabel.numberOfLines = 0
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.text = "Slot \(slot.id) · \(slotTierLabel(for: slot.id))"

        let nameLabel = UILabel()
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 0
        nameLabel.text = slotDisplayName(for: slot)

        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(nameLabel)
        titleStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rightStack = UIStackView()
        rightStack.axis = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 6

        let badgeLabel = UILabel()
        badgeLabel.font = .systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
            weight: .semibold
        )
        badgeLabel.textColor = view.tintColor
        badgeLabel.text = slotBadge(for: slot)

        rightStack.addArrangedSubview(badgeLabel)

        if let actionButton = makeSlotActionControl(for: slot) {
            rightStack.addArrangedSubview(actionButton)
        }

        topRow.addArrangedSubview(titleStack)
        topRow.addArrangedSubview(rightStack)

        let detailLabel = UILabel()
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.text = slot.id == 0
            ? "Hardware slot. Manage via Whimbrel or Android USB OTG."
            : (slot.used ? "Counter \(slot.counter)" : "Available for provisioning")

        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(detailLabel)
        return container
    }

    private func makeSlotActionControl(for slot: BleManagementSlot) -> UIView? {
        guard isOwnerView else { return nil }
        if slot.id == 1 || slot.id == localSlotId || slot.id == 0 {
            return nil
        }

        if slot.id == 2 || slot.id == 3 {
            if slot.used {
                let button = UIButton(type: .system)
                button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
                button.showsMenuAsPrimaryAction = true
                button.menu = UIMenu(children: [
                    UIAction(title: "Rename") { [weak self] _ in
                        self?.presentRenamePrompt(for: slot)
                    },
                    UIAction(title: "Replace") { [weak self] _ in
                        self?.presentReplaceConfirmation(for: slot)
                    },
                    UIAction(title: "Delete", attributes: .destructive) { [weak self] _ in
                        self?.presentDeleteConfirmation(for: slot)
                    }
                ])
                return button
            }

            return makeActionButton(title: "Add Guest Key", filled: false) { [weak self] in
                self?.presentGuestProvisionConfirmation(slotId: slot.id)
            }
        }

        return nil
    }

    private func makeSlotRow(for slot: BleManagementSlot) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 16

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        let topRow = UIStackView()
        topRow.axis = .horizontal
        topRow.alignment = .firstBaseline
        topRow.spacing = 12

        let titleLabel = UILabel()
        titleLabel.numberOfLines = 0
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.text = "Slot \(slot.id) · \(slotTierLabel(for: slot.id))"

        let badgeLabel = UILabel()
        badgeLabel.font = .systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
            weight: .semibold
        )
        badgeLabel.textColor = view.tintColor
        badgeLabel.textAlignment = .right
        badgeLabel.text = slotBadge(for: slot)

        topRow.addArrangedSubview(titleLabel)
        topRow.addArrangedSubview(badgeLabel)

        let nameLabel = UILabel()
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 0
        nameLabel.text = slotDisplayName(for: slot)

        let detailLabel = UILabel()
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.text = slot.id == 0
            ? "Hardware slot"
            : (slot.used ? "Counter \(slot.counter)" : "Available for provisioning")

        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(detailLabel)
        return container
    }

    private func makeActionButton(title: String, filled: Bool, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = filled ? UIButton.Configuration.filled() : UIButton.Configuration.bordered()
        configuration.cornerStyle = .large
        configuration.title = title
        button.configuration = configuration
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeBodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.text = text
        return label
    }

    private func makeSecondaryLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.text = text
        return label
    }

    private func makeErrorLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .systemRed
        label.text = text
        return label
    }

    private func managementStatusText(for state: BleManagementSessionState) -> String {
        switch state.connectionState {
        case .disconnected:
            return "Management session disconnected."
        case .scanning:
            return "Scanning for Guillemot management advertising."
        case .connecting:
            return "Connecting to management GATT."
        case .discovering:
            return "Discovering management characteristics."
        case .ready:
            return "Management session ready."
        case .error:
            return state.lastError ?? "Management session failed."
        }
    }

    private func slotTierLabel(for slotId: Int) -> String {
        switch slotId {
        case 0: return "HARDWARE KEY"
        case 1: return "OWNER"
        case 2, 3: return "GUEST"
        default: return "PHONE SLOT"
        }
    }

    private func slotDisplayName(for slot: BleManagementSlot) -> String {
        if !slot.name.isEmpty {
            return slot.name
        }
        if slot.id == 0 {
            return "Uguisu"
        }
        return slot.used ? "Provisioned" : "Empty"
    }

    private func slotBadge(for slot: BleManagementSlot) -> String {
        if slot.id == localSlotId {
            return "THIS PHONE"
        }
        if slot.id == 0 {
            return "HARDWARE"
        }
        return slot.used ? "ACTIVE" : "EMPTY"
    }

    private func resolveLocalPhoneSlotId() -> Int? {
#if canImport(shared)
        for slotId in 1...3 {
            if keyStore.loadKey(slotId: Int32(slotId)) != nil {
                return slotId
            }
        }
#endif
        return nil
    }

    @objc private func closeTapped() {
        onClose()
    }

    @objc private func retryTapped() {
        loadSlots()
    }

    @objc private func backgroundUnlockChanged() {
#if canImport(shared)
        appSettings.isProximityEnabled = proximitySwitch.isOn
        updateProximityUi()
#endif
    }

    @objc private func unlockSliderChanged() {
#if canImport(shared)
        let roundedUnlock = Int32(unlockSlider.value.rounded())
        let clampedUnlock = max(-95, min(-35, Int(roundedUnlock)))
        appSettings.unlockRssi = Int32(clampedUnlock)

        let maxLock = clampedUnlock - 10
        if Int(appSettings.lockRssi) > maxLock {
            appSettings.lockRssi = Int32(maxLock)
        }

        updateProximityUi()
#endif
    }

    @objc private func lockSliderChanged() {
#if canImport(shared)
        let roundedLock = Int32(lockSlider.value.rounded())
        let maxLock = Int(appSettings.unlockRssi) - 10
        let clampedLock = max(-105, min(maxLock, Int(roundedLock)))
        appSettings.lockRssi = Int32(clampedLock)
        updateProximityUi()
#endif
    }

    private func presentGuestProvisionConfirmation(slotId: Int) {
        let alert = UIAlertController(
            title: "Add a guest key?",
            message: "This will create a key for Slot \(slotId) (\(guestSlotDefaultName(slotId))). The guest will be able to lock and unlock only.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create Key", style: .default) { [weak self] _ in
            self?.provisionGuestSlot(slotId: slotId, replaceExisting: false)
        })
        present(alert, animated: true)
    }

    private func presentReplaceConfirmation(for slot: BleManagementSlot) {
        let alert = UIAlertController(
            title: "Replace \"\(slotDisplayName(for: slot))\"?",
            message: "This permanently locks out the old device and creates a new key for the replacement phone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Replace", style: .destructive) { [weak self] _ in
            self?.provisionGuestSlot(slotId: slot.id, replaceExisting: true)
        })
        present(alert, animated: true)
    }

    private func presentDeleteConfirmation(for slot: BleManagementSlot) {
        let alert = UIAlertController(
            title: "Revoke \"\(slotDisplayName(for: slot))\"?",
            message: "This device will be permanently locked out.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.performOwnerWrite(description: "Revoking slot \(slot.id)") {
                        _ = try await self.bleService.revoke(slotId: slot.id)
                    }
                } catch {
                    await MainActor.run {
                        self.presentInfoAlert(title: "Revoking slot \(slot.id)", message: error.localizedDescription)
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    private func presentRenamePrompt(for slot: BleManagementSlot) {
        let alert = UIAlertController(title: "Rename Guest Slot", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Device name"
            textField.text = self.slotDisplayName(for: slot)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let newName = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !newName.isEmpty else {
                return
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.performOwnerWrite(description: "Renaming slot \(slot.id)") {
                        _ = try await self.bleService.rename(slotId: slot.id, name: String(newName.prefix(24)))
                    }
                } catch {
                    await MainActor.run {
                        self.presentInfoAlert(title: "Renaming slot \(slot.id)", message: error.localizedDescription)
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    private func presentTransferConfirmation() {
        guard localSlotId != nil else {
            presentInfoAlert(title: "No Local Key", message: "This device does not currently store a phone key.")
            return
        }

        let alert = UIAlertController(
            title: "Transfer your key to a new phone?",
            message: "This generates a QR code for your new phone to scan. After the transfer, this phone will no longer work as a key.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Generate QR Code", style: .default) { [weak self] _ in
            guard let self else { return }
            if self.localSlotId == 1 {
                self.presentOwnerTransferPinPrompt()
            } else {
                self.presentTransferQr(pin: nil)
            }
        })
        present(alert, animated: true)
    }

    private func presentOwnerTransferPinPrompt() {
        let alert = UIAlertController(title: "Enter your 6-digit PIN", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.keyboardType = .numberPad
            textField.isSecureTextEntry = true
            textField.placeholder = "PIN"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Generate", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let pin = alert?.textFields?.first?.text?.filter(\.isNumber),
                  pin.count == 6 else {
                self?.presentInfoAlert(title: "PIN Required", message: "Owner transfer requires your 6-digit management PIN.")
                return
            }
            self.presentTransferQr(pin: pin)
        })
        present(alert, animated: true)
    }

    private func presentTransferQr(pin: String?) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.buildMigrationPayload(pin: pin)
                await MainActor.run {
                    self.presentQrSheet(
                        title: "Transfer to New Phone",
                        body: payload.body,
                        qrPayload: payload.qrPayload,
                        doneTitle: "Done — I've Scanned",
                        deleteLocalKeyOnDone: true
                    )
                }
            } catch {
                await MainActor.run {
                    self.presentInfoAlert(title: "Transfer Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func provisionGuestSlot(slotId: Int, replaceExisting: Bool) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let key = try self.randomBytes(count: 16)
                let slotName = self.guestSlotDefaultName(slotId)
                try await self.performOwnerWrite(description: replaceExisting ? "Replacing slot \(slotId)" : "Provisioning slot \(slotId)") {
                    if replaceExisting {
                        _ = try await self.bleService.revoke(slotId: slotId)
                    }
                    _ = try await self.bleService.provision(slotId: slotId, key: key, counter: 0, name: slotName)
                }

                let qrPayload = self.buildPlainProvisioningUri(slotId: slotId, key: key, counter: 0, name: slotName)
                await MainActor.run {
                    self.presentQrSheet(
                        title: replaceExisting ? "Replacement Key Ready" : "Guest Key Ready",
                        body: "Scan this on the guest phone. No PIN is required for guest provisioning.",
                        qrPayload: qrPayload,
                        doneTitle: "Done",
                        deleteLocalKeyOnDone: false
                    )
                }
            } catch {
                await MainActor.run {
                    self.presentInfoAlert(title: "Guest Provisioning Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func performOwnerWrite(description: String, action: @escaping () async throws -> Void) async throws {
        do {
            try await bleService.connectManagement(mode: .standard)
            _ = try await bleService.identify(slotId: 1)
            try await action()
            loadSlots()
        } catch {
            throw error
        }
    }

    private func presentQrSheet(
        title: String,
        body: String,
        qrPayload: String,
        doneTitle: String,
        deleteLocalKeyOnDone: Bool
    ) {
        let qrViewController = SettingsQrViewController(
            titleText: title,
            bodyText: body,
            qrPayload: qrPayload,
            doneTitle: doneTitle,
            onDone: { [weak self] in
                guard let self else { return }
                if deleteLocalKeyOnDone {
                    self.presentLocalDeletionConfirmation()
                }
            }
        )
        if let sheet = qrViewController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(qrViewController, animated: true)
    }

    private func presentLocalDeletionConfirmation() {
        guard let localSlotId else { return }
        let alert = UIAlertController(
            title: "Delete this phone's key?",
            message: "The key will be permanently deleted from this phone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete Key", style: .destructive) { [weak self] _ in
#if canImport(shared)
            self?.keyStore.deleteKey(slotId: Int32(localSlotId))
#endif
            self?.onLocalKeyDeleted()
        })
        present(alert, animated: true)
    }

    private func presentInfoAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func buildMigrationPayload(pin: String?) async throws -> (qrPayload: String, body: String) {
#if canImport(shared)
        guard let localSlotId else {
            throw IosBleProximityServiceError.system("No local key is stored on this device")
        }
        guard let storedKey = keyStore.loadKey(slotId: Int32(localSlotId)) else {
            throw IosBleProximityServiceError.system("No local key is stored for slot \(localSlotId)")
        }

        let keyData = data(from: storedKey)
        let counter = keyStore.loadCounter(slotId: Int32(localSlotId))
        let slot = completedSlots.first(where: { $0.id == localSlotId })
        let slotName = String((slot?.name.isEmpty == false ? slot?.name : defaultSlotName(for: localSlotId, used: true))?.prefix(24) ?? "Phone")

        if localSlotId == 1 {
            guard let pin, pin.count == 6 else {
                throw IosBleProximityServiceError.system("Owner transfer requires your 6-digit PIN")
            }
            try await ensureCryptoInitialized()
            let salt = try randomBytes(count: Int(ImmoCrypto.shared.QR_SALT_LEN))
            let derivedKey = ImmoCrypto.shared.deriveKey(
                pin: pin,
                salt: kotlinByteArray(from: Array(salt)),
                params: defaultArgonParams()
            )
            let encryptedKey = ImmoCrypto.shared.encryptProvisionedKey(
                derivedKey: derivedKey,
                salt: kotlinByteArray(from: Array(salt)),
                slotKey: kotlinByteArray(from: Array(keyData))
            )
            return (
                buildEncryptedProvisioningUri(
                    slotId: localSlotId,
                    salt: salt,
                    encryptedKey: data(from: encryptedKey),
                    counter: counter,
                    name: slotName
                ),
                "Scan this on your new phone. The new phone will ask for your management PIN before importing the owner key."
            )
        }

        return (
            buildPlainProvisioningUri(slotId: localSlotId, key: keyData, counter: counter, name: slotName),
            "Scan this on your new phone. Guest transfers stay plaintext and do not require a PIN."
        )
#else
        throw IosBleProximityServiceError.unsupported("Shared framework is unavailable for secure transfer")
#endif
    }

    private func buildPlainProvisioningUri(slotId: Int, key: Data, counter: UInt32, name: String) -> String {
        var components = URLComponents()
        components.scheme = "immogen"
        components.host = "prov"
        components.queryItems = [
            URLQueryItem(name: "slot", value: String(slotId)),
            URLQueryItem(name: "key", value: key.hexEncodedString()),
            URLQueryItem(name: "ctr", value: String(counter)),
            URLQueryItem(name: "name", value: name)
        ]
        return components.string ?? "immogen://prov"
    }

    private func buildEncryptedProvisioningUri(slotId: Int, salt: Data, encryptedKey: Data, counter: UInt32, name: String) -> String {
        var components = URLComponents()
        components.scheme = "immogen"
        components.host = "prov"
        components.queryItems = [
            URLQueryItem(name: "slot", value: String(slotId)),
            URLQueryItem(name: "salt", value: salt.hexEncodedString()),
            URLQueryItem(name: "ekey", value: encryptedKey.hexEncodedString()),
            URLQueryItem(name: "ctr", value: String(counter)),
            URLQueryItem(name: "name", value: name)
        ]
        return components.string ?? "immogen://prov"
    }

    private func guestSlotDefaultName(_ slotId: Int) -> String {
        switch slotId {
        case 2: return "Guest 1"
        case 3: return "Guest 2"
        default: return "Guest"
        }
    }

    private func defaultSlotName(for slotId: Int, used: Bool) -> String {
        switch slotId {
        case 0: return "Uguisu"
        case 1: return used ? "Owner Phone" : "Owner"
        case 2: return used ? "Guest 1" : "Empty"
        case 3: return used ? "Guest 2" : "Empty"
        default: return used ? "Provisioned" : "Empty"
        }
    }

    private func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            throw IosBleProximityServiceError.system("Secure random generation failed")
        }
        return Data(bytes)
    }

#if canImport(shared)
    private func ensureCryptoInitialized() async throws {
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

private extension UIStackView {
    func removeAllArrangedSubviews() {
        let subviews = arrangedSubviews
        subviews.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private final class SettingsQrViewController: UIViewController {
    private let titleText: String
    private let bodyText: String
    private let qrPayload: String
    private let doneTitle: String
    private let onDone: () -> Void
    private let qrContext = CIContext()

    init(titleText: String, bodyText: String, qrPayload: String, doneTitle: String, onDone: @escaping () -> Void) {
        self.titleText = titleText
        self.bodyText = bodyText
        self.qrPayload = qrPayload
        self.doneTitle = doneTitle
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.numberOfLines = 0
        titleLabel.text = titleText

        let bodyLabel = UILabel()
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.text = bodyText

        let imageView = UIImageView(image: generateQrImage(payload: qrPayload))
        imageView.backgroundColor = .white
        imageView.layer.cornerRadius = 20
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 280)
        ])

        let payloadLabel = UILabel()
        payloadLabel.font = .preferredFont(forTextStyle: .caption1)
        payloadLabel.textColor = .secondaryLabel
        payloadLabel.numberOfLines = 0
        payloadLabel.text = "Provisioning payload is hidden for security. Use only the QR code to transfer."

        let doneButton = UIButton(type: .system)
        var doneConfiguration = UIButton.Configuration.filled()
        doneConfiguration.cornerStyle = .large
        doneConfiguration.title = doneTitle
        doneButton.configuration = doneConfiguration
        doneButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true) {
                self?.onDone()
            }
        }, for: .touchUpInside)

        let cancelButton = UIButton(type: .system)
        var cancelConfiguration = UIButton.Configuration.bordered()
        cancelConfiguration.cornerStyle = .large
        cancelConfiguration.title = "Cancel"
        cancelButton.configuration = cancelConfiguration
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(bodyLabel)
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(payloadLabel)
        stack.addArrangedSubview(doneButton)
        stack.addArrangedSubview(cancelButton)
    }

    private func generateQrImage(payload: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = qrContext.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
