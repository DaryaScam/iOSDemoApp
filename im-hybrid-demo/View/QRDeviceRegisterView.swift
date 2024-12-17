//
//  QRDeviceRegisterView.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

import SwiftUI
import CryptoKit

struct QRDevicesRegisterView: View {
    @State private var qrresult = ""
    @State private var qrIsScanning = true
    
    private var bleManager: BluetoothManager = BluetoothManager()
        
    @State private var isConnected: Bool = false
    @State private var statusMessage: String?
    
    @State private var displayError: Error?
    @State private var showPopup: Bool = false
    @State private var showConsent: Bool = false
    @StateObject private var consentManager = ConsentManager()
        
    @StateObject private var cdp: CoreDataProvider = try! CoreDataProvider()
    
    func stopQR() {
        qrIsScanning = false
    }
    
    func startQR() {
        qrIsScanning = true
    }
    
    func showConsentButtons() {
        showConsent = true
    }
    
    func hideConsentButtons() {
        showConsent = false
    }
    
    func setPopupMessage(_ message: String?) {
        statusMessage = message
    }
    
    func dismiss() {
        self.bleManager.stopAdvertising()
        waitTime(1500) { _ in
            showPopup = false
        }
    }
    
    var body: some View {
        ReadQRView(resultCode: $qrresult, isScanning: $qrIsScanning)
            .onChange(of: qrresult) {
                do {
                    if qrresult.isEmpty {
                        return
                    }
                    
                    stopQR()
                    

                    
                    if qrresult.starts(with: "FIDO:/") {
                        Task {
                            do {
                                var webSocket: WebSocketProvider? = nil

                                // Hybrid flow [TODO]
                                let selectedDomain = CableDomain.d0269_dljqskoal33ac
                                let challengeinst = try DecodeCabLEChallenge(qrresult)
                                let advertisingData = try GenerateAdvertisingData(hybridChallenge: challengeinst, tunnelId: selectedDomain)
                                print("Scanned code: \(advertisingData.serviceData.hex) \(advertisingData.serviceData.count)")
                                
                                let wsUrl = try GenerateHybridTunnelUrl(hybridChallenge: challengeinst, routingId: advertisingData.routingId, selectedDomain: selectedDomain)
                                print("WS URL: \(wsUrl)")
                                setPopupMessage("Establishing connection...")
                                showPopup = true
                                webSocket = try await WebSocketProvider(url: wsUrl)
                                
                                
                                self.bleManager.stopAdvertising()
                                self.bleManager.startAdvertising(advertisingData.serviceData)
                                
                                // Initiate the hybrid tunnel
                                let psk = HybridHDKFDerive(inputKey: Data(challengeinst.secret), purpose: .keyPurposePSK, outputByteCount: 32)
                                
                                let initMsg: Data = try await webSocket!.awaitForRawMessage(timeout: 1000)
                                                            
                                let cable = CableV2()
                                
                                let decResponse = try cable.decryptHandshake(psk: psk, qrKeyX962: decompressESPublicKey(Data(challengeinst.publicKey)), initMsg: initMsg)
                                let ackResult = try cable.generateHandshakeAck(peerESKey: decResponse.peerESKey.privateKey, reqESX962: decResponse.reqESX962)
                                
                                let clientToPlatformKey = ackResult.trafficKeys.o1
                                let platformToClientKey = ackResult.trafficKeys.o2
                                    
                                try await webSocket!.send(data: ackResult.handhshakeAck)
                                let p1: Data = try await webSocket!.awaitForRawMessage(timeout: 1000)
                                
                                
                            } catch {
                                print("Error: \(error)")
                                displayError = error
                                dismiss()
                            }
                            
                        }
  
                    } else {
                        print("Scanned code: \(qrresult)")
                        var webSocket: WebSocketProvider? = nil

                        Task {
                            do {

                                showPopup = true
                                webSocket = try await WebSocketProvider(url: ApplicationConfig.wssUrl + "/channel/\(qrresult)")
                                try await webSocket!.initWebSessionChannel()
                                
                                setPopupMessage("Connected. Establishing session...")

                                // Generate session ECDH KEX, for educational purposes only
                                let kexM = generateEcdhKeyPair()
                                
                                // Wait for init message from web session
                                let initMessage = try await webSocket!.awaitForMessage(messageType: .message)
                                let jsonInitMessageData = initMessage.data?.data(using: .utf8)
                                let initMessageObj = try JSONDecoder().decode(PasskeyAuthInit.self, from: jsonInitMessageData!)

                                // Get user consent
                                setPopupMessage("Do you want to open new session at \(initMessageObj.browserName)?")
                                showConsentButtons()
                                let userConsented = try await consentManager.waitForUserConsent()
                                hideConsentButtons()
                                if !userConsented {
                                    throw PasskeyError.userConsentDenied("User denied consent")
                                }
                                
                                /*
                                 * We will as well send allow credID, because we want to enforce
                                 * explicit experience
                                 */
                                let allowList = [try cdp.getFirstActivePasskey()!.cred_id!]
                                let authChallenge = PasskeyAuthInitChallenge(
                                    challenge: try generateRandomBytes(32).base64Url,
                                    allowCredIds: allowList,
                                    rpId: ApplicationConfig.rpId,
                                    kexM: kexM.publicKey.base64Url
                                )
                                
                                let authChallengeData = try JSONEncoder().encode(authChallenge)
                                let authChallengeMsgWrapper = WSMessage(type: .message, data: String(data: authChallengeData, encoding: .utf8))
                                
                                try await webSocket!.send(message: authChallengeMsgWrapper)
                                
                                setPopupMessage("Waiting for authentication. Please follow the instructions on the browser screen...")
                                
                                // Waiting for attestation response
                                let authResponse = try await webSocket!.awaitForMessage(timeout: 30000, messageType: .message)

                                let authResponseData = authResponse.data?.data(using: .utf8)
                                let authResponseObj = try JSONDecoder().decode(PasskeyAuthResponse.self, from: authResponseData!)
                                
                                // Verify the response
                                let result = try verifyAuthenticatorResponse(
                                    authResp: authResponseObj,
                                    cspasskey: cdp.getFirstActivePasskey()!,
                                    allowedOrigins: ApplicationConfig.allowedOrigins,
                                    expectedRpId: ApplicationConfig.rpId
                                )
                                
                                // Check challenge, and extract client KEX
                                let decodedChallenge = try result.challenge.base64URLDecodedString()
                                let challengeParts = decodedChallenge.split(separator: ".")
                                if challengeParts.count != 2 {
                                    throw PasskeyError.invalidChallenge("Challenge has invalid format. Expected challenge.kexc")
                                }
                                
                                if challengeParts[0] != authChallenge.challenge {
                                    throw PasskeyError.invalidChallenge("Challenge does not match the expected challenge")
                                }
                                
                                
                                // Derive shared secret
                                let kexC = challengeParts[1]
                                let kexCData = try String(kexC).base64URLDecodedData()
                                
                                
                                // Generate the shared secret
                                let keyAgreement = try deriveECDHSharedSecret(privateKey: kexM.privateKey, publicKey: Data(kexCData))
                                
                                let sessionSecret = keyAgreement.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: try authChallenge.challenge.base64URLDecodedData(), outputByteCount: 32)
                                                                                                                                
                                let newToken = try generateRandomBytes(16)
                                let encryptedToken = try encryptAesGcm(data: newToken, key: sessionSecret)
                                let ackMessage = PasskeyAck(encryptedAccessToken: encryptedToken.base64Url)
                                
                                let ackMessageData = try JSONEncoder().encode(ackMessage)
                                let ackMessageWrapper = WSMessage(type: .message, data: String(data: ackMessageData, encoding: .utf8))
                                
                                try await webSocket!.send(message: ackMessageWrapper)
                                
                                let _ = try await webSocket!.awaitForMessage(timeout: 30000, messageType: .message)

                                try cdp.newSession(deviceName: initMessageObj.browserName, accessToken: Data(newToken).base64EncodedString())
                                
                                setPopupMessage("Successfully registered new device!")
                                
                                dismiss()
                                
                                print("KEX Completed")
                               
                            } catch {
                                await webSocket?.close()
                                print("Error: \(error)")
                                displayError = error
                                dismiss()
                            }
                        }
                    }
                } catch {
                    print("Error")
                    print(error)
                    displayError = error
                    
                    dismiss()
                }
                
            }
            .sheet(isPresented: $showPopup) {
                VStack {
                    Text("Connecting to device...")
                        .font(.title)
                    
                    if statusMessage != nil {
                        Text(statusMessage!)
                            .font(.title3)
                            .padding(.top, 10)
                    }
                    
                    if displayError != nil {
                        
                        Text("An error occurred while connecting to the device")
                            .font(.title2)
                            .foregroundColor(.red)
                        
                        Text(displayError!.localizedDescription)
                            .font(.title3)
                    }
                    
                    if showConsent{
                        VStack {
                            HStack {
                                Button("Consent") {
                                    consentManager.userConsented = true
                                }
                                .tint(.green)
                                .buttonStyle(.borderedProminent)
                                
                                Button("Deny") {
                                    consentManager.userConsented = false
                                }
                                .tint(.red)
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                    }
                }
                .presentationDetents([ .fraction(0.4)])
                .padding(20)
            }
            .onDisappear {
                self.dismiss()
            }

    }
}
