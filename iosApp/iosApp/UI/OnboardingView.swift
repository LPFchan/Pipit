import SwiftUI
import Combine
import AVFoundation

#if canImport(shared)
import shared
#endif

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
            let size: CGFloat = 256
            let x = (geometry.size.width - size) / 2
            let y = (geometry.size.height - size) / 2
            let r = CGRect(x: x, y: y, width: size, height: size)
            let cr: CGFloat = 22  // corner radius
            let cl: CGFloat = 30  // corner arm length
            let lw: CGFloat = 3   // line width

            // Dimmed background with cutout
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geometry.size))
                path.addRoundedRect(in: r, cornerSize: CGSize(width: cr, height: cr))
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            // Apple-style corner bracket markers
            Path { path in
                // Top-left
                path.move(to: CGPoint(x: r.minX + lw / 2, y: r.minY + cr + cl))
                path.addLine(to: CGPoint(x: r.minX + lw / 2, y: r.minY + cr))
                path.addQuadCurve(
                    to: CGPoint(x: r.minX + cr, y: r.minY + lw / 2),
                    control: CGPoint(x: r.minX + lw / 2, y: r.minY + lw / 2)
                )
                path.addLine(to: CGPoint(x: r.minX + cr + cl, y: r.minY + lw / 2))

                // Top-right
                path.move(to: CGPoint(x: r.maxX - cr - cl, y: r.minY + lw / 2))
                path.addLine(to: CGPoint(x: r.maxX - cr, y: r.minY + lw / 2))
                path.addQuadCurve(
                    to: CGPoint(x: r.maxX - lw / 2, y: r.minY + cr),
                    control: CGPoint(x: r.maxX - lw / 2, y: r.minY + lw / 2)
                )
                path.addLine(to: CGPoint(x: r.maxX - lw / 2, y: r.minY + cr + cl))

                // Bottom-right
                path.move(to: CGPoint(x: r.maxX - lw / 2, y: r.maxY - cr - cl))
                path.addLine(to: CGPoint(x: r.maxX - lw / 2, y: r.maxY - cr))
                path.addQuadCurve(
                    to: CGPoint(x: r.maxX - cr, y: r.maxY - lw / 2),
                    control: CGPoint(x: r.maxX - lw / 2, y: r.maxY - lw / 2)
                )
                path.addLine(to: CGPoint(x: r.maxX - cr - cl, y: r.maxY - lw / 2))

                // Bottom-left
                path.move(to: CGPoint(x: r.minX + cr + cl, y: r.maxY - lw / 2))
                path.addLine(to: CGPoint(x: r.minX + cr, y: r.maxY - lw / 2))
                path.addQuadCurve(
                    to: CGPoint(x: r.minX + lw / 2, y: r.maxY - cr),
                    control: CGPoint(x: r.minX + lw / 2, y: r.maxY - lw / 2)
                )
                path.addLine(to: CGPoint(x: r.minX + lw / 2, y: r.maxY - cr - cl))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
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
    @StateObject private var viewModel: OnboardingViewModel
    
    init(bleService: IosBleProximityService, onProvisioned: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(bleService: bleService, onProvisioned: onProvisioned))
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
        .sheet(isPresented: Binding(
            get: { viewModel.onboardingState == .recovery },
            set: { isPresented in
                if !isPresented && viewModel.onboardingState == .recovery {
                    viewModel.cancelRecovery()
                }
            }
        )) {
            NavigationView {
                recoveryView
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                viewModel.cancelRecovery()
                            }
                            .foregroundColor(.white)
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.fraction(0.85), .large])
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }
    
    // MARK: Camera View
    private var cameraView: some View {
        ZStack {
            QRScannerView(onScan: { code in
                DispatchQueue.main.async {
                    viewModel.handleScannedQr(code)
                }
            }, isEnabled: !viewModel.isScanLocked)
            .ignoresSafeArea()
            
            ScannerCutoutOverlay()
            
            VStack {
                Spacer()

                VStack(spacing: 8) {
                    Text("Scan QR from Whimbrel")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)

                    if let error = viewModel.scanErrorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, 32)

                #if targetEnvironment(simulator)
                if !viewModel.isScanLocked {
                    Button(action: {
                        let mockQr = "immogen://prov?slot=1&ctr=0&salt=00112233445566778899aabbccddeeff&ekey=00112233445566778899aabbccddeeff0011223344556677&name=Simulator%20Owner"
                        DispatchQueue.main.async {
                            viewModel.handleScannedQr(mockQr)
                        }
                    }) {
                        Text("DEV: Simulate Scanned QR")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.yellow)
                            .foregroundColor(.black)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 16)
                }
                
                Button(action: {
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
                }) {
                    Text("DEV: Hard Reset App & Permissions")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                }
                .padding(.bottom, 16)
                #endif

                Button(action: {
                    viewModel.startRecoveryFlow()
                }) {
                    Text("Recover key from lost phone")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.vertical, 8)
                }
                .padding(.bottom, 36)
            }
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
                // Hidden text field captures input
                SecureField("", text: $viewModel.pinCode)
                    .keyboardType(.numberPad)
                    .foregroundColor(.clear)
                    .accentColor(.clear)
                    .onChange(of: viewModel.pinCode) { newValue in
                        if newValue.count > 6 {
                            viewModel.pinCode = String(newValue.prefix(6))
                        }
                    }

                // Visual digit boxes
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
                Spacer().frame(height: 14 + 16) // match error text approx height
            }

            Spacer().frame(height: 32)

            if viewModel.isProvisioningInFlight {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                    .padding(.vertical, 4)
            } else {
                Button(action: { viewModel.confirmPin() }) {
                    Text("Continue")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            viewModel.pinCode.count == 6 ? Color.white : Color.white.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .foregroundStyle(viewModel.pinCode.count == 6 ? Color.black : Color.white.opacity(0.45))
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
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Recovery")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .padding(.top, 40)
                
                if viewModel.recoveryState == .slotPicker || viewModel.recoveryState == .ownerProof || viewModel.recoveryState == .recovering {
                    recoverySlotPickerContent
                } else {
                    Text(viewModel.statusText)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    if viewModel.recoveryState == .waitingForWindowOpen || viewModel.recoveryState == .connecting || viewModel.recoveryState == .loadingSlots {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
                
                if let error = viewModel.recoveryErrorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding()
                }
                
                Spacer()
                
                if viewModel.recoveryState == .error {
                    Button("Retry") {
                        viewModel.retryRecovery()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
    }
    
    @ViewBuilder
    private var recoverySlotPickerContent: some View {
        if viewModel.recoveryState == .slotPicker {
            Text("Select the slot to recover")
                .foregroundColor(.white)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.recoverySlots, id: \.id) { slot in
                        Button(action: {
                            viewModel.selectSlot(slot.id)
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                        Text(slot.name.isEmpty ? "Key \(slot.id)" : slot.name)
                                        .foregroundColor(viewModel.selectedSlotId == slot.id ? .blue : .white)
                                    Text(viewModel.slotTierLabel(for: slot.id))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if viewModel.selectedSlotId == slot.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(Color(.darkGray))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            
            Button("Recover Selected Slot") {
                viewModel.beginSelectedSlotRecovery()
            }
            .disabled(viewModel.selectedSlotId == nil)
            .padding()
            .background(viewModel.selectedSlotId == nil ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        } else if viewModel.recoveryState == .ownerProof {
            VStack {
                Text("Enter Owner PIN")
                    .foregroundColor(.white)
                SecureField("PIN", text: $viewModel.pinCode)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(8)
                    .padding(.horizontal, 40)
                
                if let error = viewModel.pinErrorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
                
                Button("Confirm") {
                    viewModel.confirmPin()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding(.top, 16)
            }
        } else if viewModel.recoveryState == .recovering {
            ProgressView("Recovering...")
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .foregroundColor(.white)
        }
    }
    
    // MARK: Importing View
    private var importingView: some View {
        VStack(spacing: 40) {
            QRDecryptionAnimationView()
                .frame(width: 250, height: 250)
            
            Text(viewModel.importingStatusText)
                .foregroundColor(.gray)
                .font(.headline)
        }
    }
    
    // MARK: Permission View
    private var permissionView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Enable proximity unlock?")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Pipit can automatically unlock your vehicle when you walk up to it.")
                Text("This requires \"Always Allow\" location access so the app can detect your vehicle in the background.")
                Text("Your location is never stored or transmitted.")
            }
            .foregroundColor(.gray)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button(action: {
                    viewModel.requestLocationPermission()
                }) {
                    Text("Enable Proximity")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    viewModel.skipLocationPermission()
                }) {
                    Text("Skip for Now")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 32)
        .padding(.top, 60)
    }
    
    // MARK: Success View
    private var successView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.top, 40)
                Spacer()
            }
            
            Text("You're all set.")
                .font(.title3)
                .bold()
                .foregroundColor(.white)
                .padding(.top, 20)
                .padding(.bottom, 20)
            
            VStack(spacing: 0) {
                ForEach(0..<4) { index in
                    let isCurrent = (viewModel.provisioningSuccess?.slotId == index)
                    let slotName = getSlotName(for: index)
                    let tier = index == 0 ? "HARDWARE" : (index == 1 ? "OWNER" : "GUEST")
                    
                    HStack(alignment: .top) {
                        Text("Slot \(index)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .frame(width: 60, alignment: .leading)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(slotName)
                                .foregroundColor(isCurrent ? .white : .gray)
                            Text(tier)
                                .font(.caption2)
                                .foregroundColor(isCurrent ? .blue : .gray)
                        }
                        
                        Spacer()
                        
                        if index == 0 {
                            Image(systemName: "key.fill").foregroundColor(.gray)
                        } else if isCurrent {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Spacer()
            
            Button(action: {
                viewModel.finishOnboarding()
            }) {
                Text("Done")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 32)
    }
    
    private func getSlotName(for index: Int) -> String {
        if index == 0 { return "Uguisu" }
        if index == viewModel.provisioningSuccess?.slotId { return viewModel.provisioningSuccess?.name ?? "Phone" }
        return "— empty —"
    }
}
