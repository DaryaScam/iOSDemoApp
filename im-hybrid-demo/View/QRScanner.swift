//
//  QRScanner.swift
//  im-hybrid-demo
//

import SwiftUI
import AVKit

enum Permission: String {
    case idle = "Not determined"
    case approved = "Access granted"
    case denied = "Access denied"
}

class QRScannerDelegate: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var scannedCode: String?
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metaObject = metadataObjects.first {
            guard let readableObject = metaObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let code = readableObject.stringValue else { return }
            scannedCode = code
        }
    }    
}

func GenerateCorner(degrees: Double) -> some View {
    RoundedRectangle(cornerRadius: 2, style: .circular)
        .trim(from: 0.61, to: 0.64)  // Adjust the trim to get the desired corner part
        .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        .rotationEffect(.degrees(degrees))  // Rotate by the passed degrees
}

struct CameraView: UIViewRepresentable {
    var frameSize: CGSize
    
    @Binding var session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIViewType(frame: CGRect(origin: .zero, size: frameSize))
        view.backgroundColor = .clear
        
        let cameraLayer = AVCaptureVideoPreviewLayer(session: session)
        cameraLayer.frame = .init(origin: .zero, size: frameSize)
        cameraLayer.videoGravity = .resizeAspectFill
        cameraLayer.masksToBounds = true
        view.layer.addSublayer(cameraLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
    
    }
}

struct ReadQRView: View {
    @Binding var resultCode: String
    
    @State private var isScanning: Bool = false
    @State private var session: AVCaptureSession = .init()
    
    @State private var qrOutput: AVCaptureMetadataOutput = .init()
    @State private var cameraPermission: Permission = .idle
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    @StateObject private var qrDelegate = QRScannerDelegate()

    var body: some View {
        ZStack {
            VStack {
                Text("Place QR code inside the area")
                    .font(.title3)
                
                GeometryReader {
                    let size = $0.size
                    
                    ZStack {
                        CameraView(frameSize: CGSize(width: size.width, height: size.width), session: $session)
                        
                        GenerateCorner(degrees: 90)
                        GenerateCorner(degrees: 0)
                        GenerateCorner(degrees: 180)
                        GenerateCorner(degrees: 270)
                    }
                    .frame(width: size.width, height: size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 45)
                .padding(.vertical, 20)
            }
            .padding(.vertical, 40)
        }
        .onAppear(perform: checkCameraPermission)
        .alert(errorMessage, isPresented: $showError) {
            if cameraPermission == .denied {
                Button("Settings") {
                    let settingsString = UIApplication.openSettingsURLString
                    if let settingsUrl = URL(string: settingsString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                
                Button("Cancel", role: .cancel) {}
            }
        }
        .onChange(of: qrDelegate.scannedCode) { newValue in
            resultCode = newValue ?? ""
        }
    }
    
    func checkCameraPermission() {
        Task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                cameraPermission = .approved
                setupCamera()
            case .notDetermined:
                if await AVCaptureDevice.requestAccess(for: .video) {
                    cameraPermission = .approved
                    setupCamera()
                } else {
                    cameraPermission = .denied
                }
            case .denied, .restricted:
                cameraPermission = .denied
            default: break
            }
        }
    }
    
    func setupCamera() {
        do {
            guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first else {
                presentError("UNKNOWN ERROR")
                return
            }
            
            let input = try AVCaptureDeviceInput(device: device)
            
            guard session.canAddInput(input), session.canAddOutput(qrOutput) else {
                presentError("UNKNOWN ERROR")
                return
            }
            
            session.beginConfiguration()
            session.addInput(input)
            session.addOutput(qrOutput)
            
            qrOutput.metadataObjectTypes = [.qr]
            
            qrOutput.setMetadataObjectsDelegate(qrDelegate, queue: .main)
            session.commitConfiguration()
            
            DispatchQueue.global(qos: .background).async {
                session.startRunning()
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }
    
    func presentError(_ message: String) {
        print(message)
        errorMessage = message
        showError.toggle()
    }
}


