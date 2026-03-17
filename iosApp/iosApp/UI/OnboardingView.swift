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
            case .camera:
                cameraView
            case .pin:
                pinInputView
            case .recovery:
                recoveryView
            case .importing:
                importingView
            case .locationPermission:
                permissionView
            case .success:
                successView
            }
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }
    
    // MARK: Camera View
    private var cameraView: some View {
        VStack {
            Text("Provision Device")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 20)
            
            Spacer()
            
            ZStack {
                QRScannerView(onScan: { code in
                    DispatchQueue.main.async {
                        viewModel.handleScannedQr(code)
                    }
                }, isEnabled: !viewModel.isScanLocked)
                .frame(height: 350)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                
                VStack {
                    Spacer()
                    Text("Scan a provisioning QR code")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding(.bottom, 16)
                }
            }
            .padding(.horizontal, 24)
            
            if let error = viewModel.scanErrorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding()
            }
            
            Spacer()
            
            Button(action: {
                viewModel.startRecoveryFlow()
            }) {
                Text("Recover existing device")
                    .foregroundColor(.blue)
                    .padding()
            }
            Spacer().frame(height: 40)
        }
    }
    
    // MARK: PIN Input View
    private var pinInputView: some View {
        VStack(spacing: 20) {
            Text("Enter PIN")
                .font(.title2)
                .foregroundColor(.white)
            
            Text("Enter the 6-digit PIN used to create this key.")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            SecureField("6-digit PIN", text: $viewModel.pinCode)
                .keyboardType(.numberPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal, 40)
            
            if let error = viewModel.pinErrorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            
            if viewModel.isProvisioningInFlight {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                Button(action: {
                    viewModel.confirmPin()
                }) {
                    Text("Unlock")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            Button("Cancel") {
                viewModel.returnToCamera()
            }
            .foregroundColor(.white)
            .padding(.bottom, 40)
        }
        .padding(.top, 60)
    }
    
    // MARK: Recovery View
    private var recoveryView: some View {
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
            
            Button("Cancel") {
                viewModel.cancelRecovery()
            }
            .foregroundColor(.white)
            .padding(.bottom, 40)
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
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text(viewModel.importingStatusText)
                .foregroundColor(.white)
                .font(.headline)
        }
    }
    
    // MARK: Permission View
    private var permissionView: some View {
        VStack(spacing: 24) {
            Text("Location Permission")
                .font(.title)
                .foregroundColor(.white)
            
            Text("Pipit requires Location Permission to reliably connect to the device in the background. Please select 'Always Allow'.")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Allow Location") {
                viewModel.requestLocationPermission()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }
    
    // MARK: Success View
    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.green)
                .padding(.top, 60)
            
            Text("Successfully Provisioned!")
                .font(.title)
                .bold()
                .foregroundColor(.white)
            
            Spacer()
            
            Button("Continue") {
                viewModel.finishOnboarding()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}
