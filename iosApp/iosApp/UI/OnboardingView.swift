import SwiftUI
import Combine
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

#if canImport(shared)
import shared
#endif

private enum OnboardingMockup {
    static let accentBlue = Color(red: 0.039, green: 0.518, blue: 1.000) // Estimated from the CTA fill in the mockup.
    static let linkBlue = Color(red: 0.039, green: 0.518, blue: 1.000) // Estimated from the secondary link color in the mockup.
    static let recoverySheetBackground = Color(red: 0.238, green: 0.238, blue: 0.250).opacity(0.36) // Estimated from the darker smoky tint layered over the native sheet blur.
    static let successCardBackground = Color(red: 0.149, green: 0.149, blue: 0.161) // Estimated from the slot summary card.
    static let closeButtonFill = Color.white.opacity(0.15) // Estimated from the circular close affordance.
    static let closeButtonSymbol = Color.white.opacity(0.62) // Estimated from the close symbol tint.
    static let secondaryText = Color.white.opacity(0.88)
    static let tertiaryText = Color(red: 0.545, green: 0.545, blue: 0.572) // Estimated from secondary copy in the mockup.
    static let mutedText = Color.white.opacity(0.26)
    static let divider = Color.white.opacity(0.10)
    static let inactiveBadge = Color(red: 0.666, green: 0.666, blue: 0.705) // Estimated from the inactive guest badges.
    static let scanButtonShadow = Color.black.opacity(0.28) // Estimated from the button depth in the mockup.

    static let appTitleSize: CGFloat = 26 // Estimated from the top "Pipit" title.
    static let scanLabelFontSize: CGFloat = 23 // Estimated from the larger "Scan from Whimbrel" text in the mockup.
    static let recoveryTitleSize: CGFloat = 16 // Estimated from the compact sheet title sizing in the mockup.
    static let recoveryBodySize: CGFloat = 15 // Estimated from the recovery instruction copy in the mockup.
    static let decodingLabelSize: CGFloat = 28 // Estimated from "Decoding...".
    static let permissionTitleSize: CGFloat = 32 // Estimated from "Proximity Unlock".
    static let permissionBodySize: CGFloat = 17 // Estimated from the three permission paragraphs.
    static let successTitleSize: CGFloat = 31 // Estimated from "All set!".
    static let successSlotLabelSize: CGFloat = 11 // Estimated from the left-side SLOT labels in the success card.
    static let slotNameSize: CGFloat = 16 // Estimated from the slot row primary label.
    static let slotMetaSize: CGFloat = 11 // Estimated from the SLOT label and tier pill typography.
    static let successButtonTitleSize: CGFloat = 17 // Estimated from the success CTA label.

    static let primaryButtonCornerRadius: CGFloat = 19 // Estimated from the rounded CTA corners.
    static let recoverySheetCornerRadius: CGFloat = 30 // Estimated from the recovery sheet rounding in the mockup.
    static let slotCardCornerRadius: CGFloat = 21 // Estimated from the success card rounding.
    static let closeButtonDiameter: CGFloat = 38 // Estimated from the circular close control.
    static let recoverySheetHeight: CGFloat = 468 // Estimated from the shorter visible bottom sheet height in the reference.
    /// 3D Uguisu demo in the recovery sheet (WKWebView); taller slot so the scaled model fills the pane.
    static let recoveryFobDemoHeight: CGFloat = 280
    static let recoveryMessageHorizontalPadding: CGFloat = 46 // Estimated from the message width in the reference.
    static let recoveryMessageToSpinnerGap: CGFloat = 42 // Estimated from the tighter message-to-spinner spacing in the reference.
    static let recoveryStatusBottomPadding: CGFloat = 16 // Estimated from the tighter spinner-to-home-indicator spacing in the reference.
    static let primaryButtonHeight: CGFloat = 58 // Estimated from the permission and success CTA height.
    static let scannerCutoutSize: CGFloat = 246 // Estimated from the smaller scanning window width in the mockup.
    static let scannerCutoutCornerRadius: CGFloat = 34 // Estimated from the more rounded scanning window corners in the mockup.
    static let scanLabelTopGap: CGFloat = 20 // Estimated vertical gap from the cutout bottom to the scan label.
    static let qrPreviewSize: CGFloat = 378 // Estimated from the decoding QR preview width.
    static let successRowHeight: CGFloat = 58 // Estimated from the row block height in the reference success card.
    static let successTopSpacer: CGFloat = 36 // Estimated from the top safe-area offset to the confirmation icon.
    static let successIconSize: CGFloat = 72 // Estimated from the confirmation glyph scale.
    static let successIconBottomGap: CGFloat = 22 // Estimated icon-to-title spacing.
    static let successTitleBottomGap: CGFloat = 18 // Estimated title-to-card spacing.
    static let successCardHorizontalPadding: CGFloat = 48 // Estimated outer inset of the summary card.
    static let successButtonHorizontalPadding: CGFloat = 48 // Estimated outer inset of the success CTA.
    static let successButtonBottomPadding: CGFloat = 76 // Estimated bottom inset of the success CTA.
    static let successButtonHeight: CGFloat = 47 // Estimated success CTA height.
    static let successButtonCornerRadius: CGFloat = 18 // Estimated success CTA radius.
    static let slotRowLeadingPadding: CGFloat = 14 // Estimated inner leading inset of each summary row.
    static let slotRowTrailingPadding: CGFloat = 20 // Estimated inner trailing inset of each summary row.
    static let slotRowTopPadding: CGFloat = 14 // Estimated top inset of the row content.
    static let slotRowBottomPadding: CGFloat = 2 // Estimated bottom inset of the row content.
    static let slotRowSpacing: CGFloat = 12 // Estimated spacing between slot label, content, and accessory.
    static let slotLabelWidth: CGFloat = 44 // Estimated width of the slot label column.
    static let slotLabelTopPadding: CGFloat = 4 // Estimated offset to align the slot label with the row content.
    static let slotContentSpacing: CGFloat = 7 // Estimated title-to-badge spacing.
    static let slotBadgeHorizontalPadding: CGFloat = 8 // Estimated badge horizontal inset.
    static let slotBadgeVerticalPadding: CGFloat = 3 // Estimated badge vertical inset.
    static let slotAccessoryTopPadding: CGFloat = 5 // Estimated offset to align the accessory with the row content.
}

private struct QrPayloadPreview: View {
    let payload: String?

    var body: some View {
        Group {
            if let payload, let image = makeImage(from: payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .padding(28) // Estimated fallback padding for the empty state.
                    .foregroundStyle(.black)
                    .background(Color.white)
            }
        }
        .background(Color.white)
    }

    private func makeImage(from payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) // Estimated scale to match the mockup QR density.
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct SuccessOverviewRow: Identifiable {
    let id: Int
    let title: String
    let tier: String
    let isActive: Bool
    let isCurrentDevice: Bool
}

struct SlotPresentationRow: Identifiable {
    let id: Int
    let title: String
    let tier: String
    let isActive: Bool
    let isCurrentDevice: Bool
    let detail: String?

    init(
        id: Int,
        title: String,
        tier: String,
        isActive: Bool,
        isCurrentDevice: Bool = false,
        detail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.tier = tier
        self.isActive = isActive
        self.isCurrentDevice = isCurrentDevice
        self.detail = detail
    }
}

struct SlotPresentationStyle {
    let background: Color
    let border: Color
    let slotLabel: Color
    let activeTitle: Color
    let inactiveTitle: Color
    let activeDetail: Color
    let inactiveDetail: Color
    let activeBadgeBackground: Color
    let inactiveBadgeBackground: Color
    let activeBadgeText: Color
    let inactiveBadgeText: Color
    let divider: Color
    let currentDeviceTint: Color
    let accessoryTint: Color

    static let onboardingDark = SlotPresentationStyle(
        background: OnboardingMockup.successCardBackground,
        border: .clear,
        slotLabel: OnboardingMockup.mutedText,
        activeTitle: .white,
        inactiveTitle: OnboardingMockup.tertiaryText,
        activeDetail: OnboardingMockup.secondaryText,
        inactiveDetail: OnboardingMockup.mutedText,
        activeBadgeBackground: OnboardingMockup.accentBlue,
        inactiveBadgeBackground: OnboardingMockup.inactiveBadge,
        activeBadgeText: .white,
        inactiveBadgeText: .white,
        divider: OnboardingMockup.divider,
        currentDeviceTint: OnboardingMockup.accentBlue,
        accessoryTint: Color.white.opacity(0.92)
    )

    static let settingsGrouped = SlotPresentationStyle(
        background: Color(UIColor.secondarySystemGroupedBackground),
        border: .clear,
        slotLabel: Color.secondary,
        activeTitle: .primary,
        inactiveTitle: Color.secondary,
        activeDetail: Color.secondary,
        inactiveDetail: Color.secondary.opacity(0.7),
        activeBadgeBackground: OnboardingMockup.accentBlue,
        inactiveBadgeBackground: Color(UIColor.tertiarySystemFill),
        activeBadgeText: .white,
        inactiveBadgeText: .primary,
        divider: Color(UIColor.separator),
        currentDeviceTint: OnboardingMockup.accentBlue,
        accessoryTint: Color.secondary
    )
}

struct SlotPresentationCard: View {
    let rows: [SlotPresentationRow]
    var style: SlotPresentationStyle = .onboardingDark
    var rowMinHeight: CGFloat = OnboardingMockup.successRowHeight
    var accessoryWidth: CGFloat = 24
    var accessory: ((SlotPresentationRow) -> AnyView)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .top, spacing: OnboardingMockup.slotRowSpacing) {
                    Text("SLOT \(row.id + 1)")
                        .font(.system(size: OnboardingMockup.successSlotLabelSize, weight: .regular))
                        .foregroundStyle(style.slotLabel)
                        .frame(width: OnboardingMockup.slotLabelWidth, alignment: .leading)
                        .padding(.top, OnboardingMockup.slotLabelTopPadding)

                    VStack(alignment: .leading, spacing: OnboardingMockup.slotContentSpacing) {
                        Text(row.title)
                            .font(.system(size: OnboardingMockup.slotNameSize, weight: row.isActive ? .semibold : .medium))
                            .foregroundStyle(row.isActive ? style.activeTitle : style.inactiveTitle)
                            .lineLimit(2)

                        Text(row.tier)
                            .font(.system(size: OnboardingMockup.slotMetaSize, weight: .semibold))
                            .foregroundStyle(row.isActive ? style.activeBadgeText : style.inactiveBadgeText)
                            .padding(.horizontal, OnboardingMockup.slotBadgeHorizontalPadding)
                            .padding(.vertical, OnboardingMockup.slotBadgeVerticalPadding)
                            .background(row.isActive ? style.activeBadgeBackground : style.inactiveBadgeBackground, in: Capsule())

                        if let detail = row.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(row.isActive ? style.activeDetail : style.inactiveDetail)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    accessoryView(for: row)
                        .padding(.top, OnboardingMockup.slotAccessoryTopPadding)
                        .frame(width: accessoryWidth, alignment: .trailing)
                }
                .frame(minHeight: rowMinHeight, alignment: .top)
                .padding(.leading, OnboardingMockup.slotRowLeadingPadding)
                .padding(.trailing, OnboardingMockup.slotRowTrailingPadding)
                .padding(.top, OnboardingMockup.slotRowTopPadding)
                .padding(.bottom, row.detail == nil ? OnboardingMockup.slotRowBottomPadding : 10)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(style.divider)
                        .frame(height: 0.5)
                }
            }
        }
        .background(style.background)
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingMockup.slotCardCornerRadius, style: .continuous)
                .stroke(style.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: OnboardingMockup.slotCardCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func accessoryView(for row: SlotPresentationRow) -> some View {
        if let accessory {
            accessory(row)
        } else if row.isCurrentDevice {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(style.currentDeviceTint)
                .offset(x: 2, y: -2)
        } else {
            Color.clear.frame(height: 0)
        }
    }
}

// MARK: - Scanner

struct QRScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var isEnabled: Bool

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRScannerView
        
        init(parent: QRScannerView) {
            self.parent = parent
        }
        
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard parent.isEnabled else { return }
            if let metadataObject = metadataObjects.first,
               let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
               let stringValue = readableObject.stringValue {
                parent.onScan(stringValue)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        let session = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return viewController }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return viewController
        }
        
        if (session.canAddInput(videoInput)) {
            session.addInput(videoInput)
        } else {
            return viewController
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (session.canAddOutput(metadataOutput)) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return viewController
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = viewController.view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        viewController.view.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .background).async {
            session.startRunning()
        }
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard let previewLayer = uiViewController.view.layer.sublayers?.first as? AVCaptureVideoPreviewLayer else { return }
        previewLayer.frame = uiViewController.view.layer.bounds
        
        if let session = previewLayer.session {
            if isEnabled && !session.isRunning {
                DispatchQueue.global(qos: .background).async {
                    session.startRunning()
                }
            } else if !isEnabled && session.isRunning {
                session.stopRunning()
            }
        }
    }
}

struct ScannerCutoutOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let size = OnboardingMockup.scannerCutoutSize
            let x = (geometry.size.width - size) / 2
            let y = (geometry.size.height - size) / 2
            let r = CGRect(x: x, y: y, width: size, height: size)
            let cr = OnboardingMockup.scannerCutoutCornerRadius

            // Dimmed background with cutout
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geometry.size))
                path.addRoundedRect(in: r, cornerSize: CGSize(width: cr, height: cr))
            }
            .fill(Color.black.opacity(0.68), style: FillStyle(eoFill: true)) // Estimated from the darker surrounding mask in the mockup.
        }
        .ignoresSafeArea()
    }
}

struct QRDecryptionAnimationView: View {
    @State private var phase: Int = 0 // 0: Start, 1: Dissolve, 2: Converge, 3: Resolve
    
    var body: some View {
        ZStack {
            if phase < 3 {
                // Particles
                ForEach(0..<20, id: \.self) { i in
                    Rectangle()
                        .fill(phase < 2 ? Color.white : Color.blue)
                        .frame(width: 8, height: 8)
                        .offset(
                            x: phase == 0 ? 0 : (phase == 1 ? CGFloat.random(in: -100...100) : 0),
                            y: phase == 0 ? 0 : (phase == 1 ? CGFloat.random(in: -100...100) : 0)
                        )
                        .rotationEffect(.degrees(phase == 1 ? Double.random(in: 0...360) : 0))
                        .opacity(phase == 0 ? 0 : (phase == 2 ? 0 : 1))
                        .animation(.easeInOut(duration: 0.4), value: phase)
                }
            } else {
                Image(systemName: "key.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .foregroundColor(.blue)
                    .shadow(color: .blue, radius: 10, x: 0, y: 0)
                    .transition(.scale.combined(with: .opacity))
                    .onAppear {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { phase = 1 } // Dissolve
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { phase = 2 } // Converge
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(.spring()) { phase = 3 } } // Resolve
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    @StateObject private var recoveryFobPool = RecoveryFobWebViewPool()

    init(bleService: IosBleProximityService, onProvisioned: @escaping () -> Void) {
        _viewModel = State(initialValue: OnboardingViewModel(bleService: bleService, onProvisioned: onProvisioned))
    }

    private var isRecoverySheetPresented: Bool {
        viewModel.onboardingState == .recovery
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.onboardingState {
            case .camera, .recovery:
                cameraView
            case .pin:
                pinInputView
            case .importing:
                importingView
            case .locationPermission:
                permissionView
            case .success:
                successView
            }
        }
        .sheet(isPresented: recoverySheetBinding) {
            recoveryView
                .presentationDetents([.height(OnboardingMockup.recoverySheetHeight)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(OnboardingMockup.recoverySheetCornerRadius)
                .presentationBackground(.ultraThinMaterial)
                .interactiveDismissDisabled(viewModel.recoveryState == .recovering)
                .preferredColorScheme(.dark)
        }
        .animation(.easeInOut(duration: 0.24), value: viewModel.onboardingState)
        .animation(.easeInOut(duration: 0.24), value: viewModel.recoveryState)
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    private var recoverySheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.onboardingState == .recovery },
            set: { isPresented in
                if !isPresented && viewModel.onboardingState == .recovery {
                    viewModel.cancelRecovery()
                }
            }
        )
    }

    private var pinCodeBinding: Binding<String> {
        Binding(
            get: { viewModel.pinCode },
            set: { viewModel.pinCode = $0 }
        )
    }

    // MARK: Camera View
    private var cameraView: some View {
        GeometryReader { geometry in
            let scanLabelTopInset = ((geometry.size.height - OnboardingMockup.scannerCutoutSize) / 2) + OnboardingMockup.scannerCutoutSize + OnboardingMockup.scanLabelTopGap

            ZStack {
                QRScannerView(onScan: { code in
                    DispatchQueue.main.async {
                        viewModel.handleScannedQr(code)
                    }
                }, isEnabled: !viewModel.isScanLocked)
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.68), Color.black.opacity(0.18), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 210) // Estimated from the top fade depth in the mockup.

                    Spacer(minLength: 0)

                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.14), Color.black.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 320) // Estimated from the bottom readability fade in the mockup.
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScannerCutoutOverlay()

                // Prewarm / park the pooled `WKWebView` while on QR or recovery (sheet steals the web view when open).
                if viewModel.onboardingState == .camera || viewModel.onboardingState == .recovery {
                    RecoveryFobAnchor(
                        pool: recoveryFobPool,
                        shouldAttach: !isRecoverySheetPresented
                    )
                    .frame(width: 340, height: OnboardingMockup.recoveryFobDemoHeight)
                    .opacity(0.004)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .position(x: -500, y: geometry.size.height * 0.35)
                }

                VStack(spacing: 0) {
                    Text("Pipit")
                        .font(.system(size: OnboardingMockup.appTitleSize, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)

                    Spacer()

                    Button(action: {
                        viewModel.startRecoveryFlow()
                    }) {
                        Text("Forgot your old phone?")
                            .font(.system(size: 17, weight: .medium)) // Estimated from the link copy.
                            .foregroundStyle(OnboardingMockup.linkBlue)
                            .padding(.vertical, 12)
                    }
                    .padding(.bottom, 20)
                }

                VStack(spacing: 14) {
                    if let error = viewModel.scanErrorMessage {
                        Text(error)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 24)
                    }

                    Text("Scan from Whimbrel")
                        .font(.system(size: OnboardingMockup.scanLabelFontSize, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, scanLabelTopInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                #if targetEnvironment(simulator)
                VStack {
                    HStack {
                        Spacer()

                        Menu {
                            Button("Simulate guest QR (slot 3)") {
                                viewModel.handleScannedQr(simulatorGuestMockQr)
                            }

                            Button("Simulate owner QR (slot 1)") {
                                viewModel.handleScannedQr(simulatorOwnerMockQr)
                            }

                            Button("Hard reset app and permissions", role: .destructive) {
                                performSimulatorHardReset()
                            }
                        } label: {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Color.black.opacity(0.46), in: Circle())
                        }
                        .padding(.top, 18)
                        .padding(.trailing, 18)
                    }

                    Spacer()
                }
                #endif
            }
            .onAppear {
                recoveryFobPool.ensureWebViewCreated()
            }
        }
    }

    private var simulatorGuestMockQr: String {
        "immogen://prov?slot=3&ctr=0&key=00112233445566778899aabbccddeeff&name=Guest%20iPhone"
    }

    private var simulatorOwnerMockQr: String {
        "immogen://prov?slot=1&ctr=0&salt=00112233445566778899aabbccddeeff&ekey=00112233445566778899aabbccddeeff0011223344556677&name=Owner%20iPhone"
    }

    private func performSimulatorHardReset() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        #if canImport(shared)
        let keyStore = KeyStoreManager()
        for i in 1...6 {
            keyStore.deleteKey(slotId: Int32(i))
        }
        #endif

        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
        }
    }

    // MARK: PIN Input View
    private var pinInputView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .padding(.bottom, 6)

                Text("Enter PIN")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text("The 6-digit PIN set during Guillemot setup.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer().frame(height: 52)

            ZStack {
                SecureField("", text: pinCodeBinding)
                    .keyboardType(.numberPad)
                    .foregroundColor(.clear)
                    .accentColor(.clear)
                    .textContentType(.oneTimeCode)
                    .onChange(of: viewModel.pinCode) { newValue in
                        if newValue.count > 6 {
                            viewModel.pinCode = String(newValue.prefix(6))
                        }
                    }

                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { index in
                        pinDigitBox(index: index)
                    }
                }
                .allowsHitTesting(false)
            }

            if let error = viewModel.pinErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Spacer().frame(height: 30)
            }

            Spacer().frame(height: 32)

            if viewModel.isProvisioningInFlight {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                    .padding(.vertical, 4)
            } else {
                Button(action: { viewModel.confirmPin() }) {
                    Text("Continue")
                        .font(.system(size: 20, weight: .bold)) // Estimated from the CTA typography.
                        .frame(maxWidth: .infinity)
                        .frame(height: OnboardingMockup.primaryButtonHeight)
                        .background(
                            viewModel.pinCode.count == 6 ? OnboardingMockup.accentBlue : Color.white.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: OnboardingMockup.primaryButtonCornerRadius, style: .continuous)
                        )
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 32)
                .disabled(viewModel.pinCode.count != 6)
                .animation(.easeInOut(duration: 0.18), value: viewModel.pinCode.count)
            }

            Spacer()

            Button("Cancel") { viewModel.returnToCamera() }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 44)
        }
    }

    private func pinDigitBox(index: Int) -> some View {
        let filled = index < viewModel.pinCode.count
        return ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(filled ? 0.18 : 0.07))
                .frame(width: 46, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(filled ? Color.white.opacity(0.75) : Color.white.opacity(0.18),
                                lineWidth: filled ? 1.5 : 1)
                )

            if filled {
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: filled)
    }

    // MARK: Recovery View
    private var recoveryView: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                Text("Recover Phone Key")
                    .font(.system(size: OnboardingMockup.recoveryTitleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                Button(action: {
                    viewModel.cancelRecovery()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OnboardingMockup.closeButtonSymbol)
                        .frame(width: OnboardingMockup.closeButtonDiameter, height: OnboardingMockup.closeButtonDiameter)
                        .background(OnboardingMockup.closeButtonFill, in: Circle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18) // Estimated to match native sheet header spacing under the drag indicator.

            recoveryBodyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OnboardingMockup.recoverySheetBackground)
        .onAppear {
            recoveryFobPool.recoverySheetBecamePresented(true)
        }
        .onDisappear {
            recoveryFobPool.recoverySheetBecamePresented(false)
        }
    }

    private var waitingRecoveryMessage: String {
        "To recover your Phone Key,\nTriple-press Uguisu to continue..."
    }

    @ViewBuilder
    private func recoveryBottomStatus(message: String) -> some View {
        VStack(spacing: 0) {
            ZStack {
                RecoveryFobAnchor(pool: recoveryFobPool, shouldAttach: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: OnboardingMockup.recoveryFobDemoHeight)
                    .background(Color.clear)

                if !recoveryFobPool.isModelReady {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.08)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            Spacer(minLength: 12)

            VStack(spacing: 0) {
                Text(message)
                    .font(.system(size: OnboardingMockup.recoveryBodySize, weight: .medium))
                    .foregroundStyle(OnboardingMockup.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, OnboardingMockup.recoveryMessageHorizontalPadding)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: OnboardingMockup.recoveryMessageToSpinnerGap)

                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.08)
            }
            .padding(.bottom, OnboardingMockup.recoveryStatusBottomPadding)
        }
    }

    @ViewBuilder
    private var recoveryBodyContent: some View {
        switch viewModel.recoveryState {
        case .slotPicker:
            VStack(spacing: 18) {
                Text("Choose the phone key slot to recover.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(OnboardingMockup.tertiaryText)
                    .padding(.top, 30)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(viewModel.recoverySlots, id: \.id) { slot in
                            Button(action: {
                                viewModel.selectSlot(slot.id)
                            }) {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("SLOT \(slot.id)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(OnboardingMockup.mutedText)

                                        Text(slot.name.isEmpty ? "Recovered Key" : slot.name)
                                            .font(.system(size: 19, weight: .semibold))
                                            .foregroundStyle(.white)

                                        Text(slot.id == 1 ? "OWNER" : "GUEST")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(slot.id == 1 ? OnboardingMockup.accentBlue : Color.white.opacity(0.10), in: Capsule())
                                    }

                                    Spacer()

                                    if viewModel.selectedSlotId == slot.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundStyle(OnboardingMockup.accentBlue)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 18)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous)) // Estimated from the row card radius.
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(viewModel.selectedSlotId == slot.id ? OnboardingMockup.accentBlue.opacity(0.72) : Color.white.opacity(0.06), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Button(action: {
                    viewModel.beginSelectedSlotRecovery()
                }) {
                    Text("Recover Selected Slot")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: OnboardingMockup.primaryButtonHeight)
                        .background(viewModel.selectedSlotId == nil ? Color.white.opacity(0.14) : OnboardingMockup.accentBlue, in: RoundedRectangle(cornerRadius: OnboardingMockup.primaryButtonCornerRadius, style: .continuous))
                }
                .disabled(viewModel.selectedSlotId == nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }

        case .ownerProof:
            VStack(spacing: 0) {
                Text("Enter the existing owner PIN to continue.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(OnboardingMockup.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 38)

                Spacer().frame(height: 34)

                ZStack {
                    SecureField("", text: pinCodeBinding)
                        .keyboardType(.numberPad)
                        .foregroundColor(.clear)
                        .accentColor(.clear)
                        .textContentType(.oneTimeCode)
                        .onChange(of: viewModel.pinCode) { newValue in
                            if newValue.count > 6 {
                                viewModel.pinCode = String(newValue.prefix(6))
                            }
                        }

                    HStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { index in
                            pinDigitBox(index: index)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .padding(.horizontal, 28)

                if let error = viewModel.pinErrorMessage {
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.92))
                        .padding(.top, 18)
                }

                Spacer()

                Button(action: {
                    viewModel.confirmPin()
                }) {
                    Text("Confirm")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: OnboardingMockup.primaryButtonHeight)
                        .background(viewModel.pinCode.count == 6 ? OnboardingMockup.accentBlue : Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: OnboardingMockup.primaryButtonCornerRadius, style: .continuous))
                }
                .disabled(viewModel.pinCode.count != 6)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }

        case .error:
            VStack(spacing: 18) {
                Spacer()

                Text(viewModel.recoveryErrorMessage ?? "Recovery failed.")
                    .font(.system(size: OnboardingMockup.recoveryBodySize, weight: .medium))
                    .foregroundStyle(OnboardingMockup.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 40)

                Button(action: {
                    viewModel.retryRecovery()
                }) {
                    Text("Retry")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: OnboardingMockup.primaryButtonHeight)
                        .background(OnboardingMockup.accentBlue, in: RoundedRectangle(cornerRadius: OnboardingMockup.primaryButtonCornerRadius, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }

        case .recovering:
            recoveryBottomStatus(message: viewModel.statusText)

        case .waitingForWindowOpen, .connecting, .loadingSlots:
            recoveryBottomStatus(message: viewModel.recoveryState == .waitingForWindowOpen ? waitingRecoveryMessage : viewModel.statusText)
        }
    }

    // MARK: Importing View
    private var importingView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 88)

            QrPayloadPreview(payload: viewModel.lastScannedQrPayload)
                .frame(width: OnboardingMockup.qrPreviewSize, height: OnboardingMockup.qrPreviewSize)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous)) // Estimated minimal corner easing from the mockup QR tile.
                .padding(.bottom, 36)

            Text("Decoding...")
                .font(.system(size: OnboardingMockup.decodingLabelSize, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.80))

            Spacer()
        }
    }

    // MARK: Permission View
    private var permissionView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 110)

            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 74, weight: .regular)) // Estimated from the icon scale in the mockup.
                .foregroundStyle(.white)
                .padding(.bottom, 34)

            Text("Proximity Unlock")
                .font(.system(size: OnboardingMockup.permissionTitleSize, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.bottom, 40)

            VStack(spacing: 22) {
                Text("Pipit can automatically unlock your vehicle when you walk up to it.")
                Text("This requires \"Always Allow\" location access so the app can detect your vehicle in the background.")
                Text("Your location is never stored or transmitted.")
            }
            .font(.system(size: OnboardingMockup.permissionBodySize, weight: .regular))
            .foregroundStyle(OnboardingMockup.secondaryText)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.horizontal, 44)

            Spacer()

            VStack(spacing: 18) {
                Button(action: { viewModel.requestLocationPermission() }) {
                    Text("Enable Proximity")
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: OnboardingMockup.primaryButtonHeight)
                        .background(OnboardingMockup.accentBlue, in: RoundedRectangle(cornerRadius: OnboardingMockup.primaryButtonCornerRadius, style: .continuous))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)

                Button(action: { viewModel.skipLocationPermission() }) {
                    Text("Skip for Now")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(OnboardingMockup.linkBlue)
                }
            }
            .padding(.bottom, 34)
        }
    }

    // MARK: Success View
    private var successView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(maxHeight: OnboardingMockup.successTopSpacer * 2)

            Image(systemName: "checkmark.circle")
                .font(.system(size: OnboardingMockup.successIconSize, weight: .regular))
                .foregroundStyle(.white)
                .padding(.bottom, OnboardingMockup.successIconBottomGap)

            Text("All set!")
                .font(.system(size: OnboardingMockup.successTitleSize, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.bottom, OnboardingMockup.successTitleBottomGap)

            SlotPresentationCard(rows: successRows.map {
                SlotPresentationRow(
                    id: $0.id,
                    title: $0.title,
                    tier: $0.tier,
                    isActive: $0.isActive,
                    isCurrentDevice: $0.isCurrentDevice
                )
            })
            .padding(.horizontal, OnboardingMockup.successCardHorizontalPadding)

            Spacer()

            Button(action: { viewModel.finishOnboarding() }) {
                Text("Done")
                    .font(.system(size: 20, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: OnboardingMockup.primaryButtonHeight)
                    .background(OnboardingMockup.accentBlue, in: RoundedRectangle(cornerRadius: OnboardingMockup.primaryButtonCornerRadius, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 74) // Adjusted to precisely match Proximity View's visually equivalent spacing
        }
    }

    private var successRows: [SuccessOverviewRow] {
        let recoveredById = Dictionary(uniqueKeysWithValues: viewModel.successOverviewSlots.map { ($0.id, $0) })

        return (0...3).map { slotId in
            let currentProvisionedSlot = viewModel.provisioningSuccess?.slotId == slotId
            let recoveredSlot = recoveredById[slotId]
            let title: String
            let isActive: Bool

            if slotId == 0 {
                let recoveredName = recoveredSlot?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                title = recoveredName?.isEmpty == false ? recoveredName! : "Uguisu"
                isActive = true
            } else if let recoveredSlot, recoveredSlot.used {
                let recoveredName = recoveredSlot.name.trimmingCharacters(in: .whitespacesAndNewlines)
                title = recoveredName.isEmpty ? "Phone Key" : recoveredName
                isActive = true
            } else if currentProvisionedSlot {
                title = viewModel.provisioningSuccess?.name ?? "Phone Key"
                isActive = true
            } else {
                title = "EMPTY"
                isActive = false
            }

            return SuccessOverviewRow(
                id: slotId,
                title: title,
                tier: slotTier(for: slotId),
                isActive: isActive || slotId == 0,
                isCurrentDevice: currentProvisionedSlot
            )
        }
    }

    private func slotTier(for slotId: Int) -> String {
        switch slotId {
        case 0:
            return "FOB"
        case 1:
            return "OWNER"
        default:
            return "GUEST"
        }
    }
}
