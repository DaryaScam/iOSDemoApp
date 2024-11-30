//
//  QRDeviceRegisterView.swift
//  im-hybrid-demo
//

import SwiftUI
import CryptoKit

struct QRDevicesRegisterView: View {    
    @State private var qrresult = ""
    private var bleManager = BluetoothManager()
    private var cdp: CoreDataProvider = try! CoreDataProvider()
    @State private var sessions: [CSSession] = []
    
    @State private var ws: WebSocketProvider?
    @State private var wsIsProcessing: Bool = false
    
    

    var body: some View {
        VStack {
            Text("Registered Devices")
                .font(.title)
            
            NavigationStack {
                List{
                    
               
                    if sessions.isEmpty {
                        Text("No devices registered")
                    } else {
                        ForEach(sessions, id: \.self) { session in
                            HStack {
                                Image(systemName: "network")
                                Text(session.device_name!)
                                
                                Spacer()
                                Text("Registered on \(localizedDateTimeString(from: session.created_at!))") // Placeholder, update dynamically if needed
                                    .font(.caption)
                            }
                            
                        }
                        .onDelete { IndexSet in
                            do {
                                try cdp.deleteSession(session: sessions[IndexSet.first!])
                                
                            } catch {
                                print("Error")
                                print(error)
                            }
                        }
                    }
                    
                    NavigationLink(destination: {
                        
                        ReadQRView(resultCode: $qrresult)
                            .onChange(of: qrresult) {
                                do {
                                    if qrresult.isEmpty {
                                        return
                                    }
                                    
                                    if qrresult.starts(with: "FIDO:/") {
                                        // Hybrid flow [TODO]
                                        let challengeinst = try DecodeCabLEChallenge($0)
                                        let advertisingData = try GenerateAdvertisingData(challengeinst)
    
                                        bleManager.startAdvertising(advertisingData)
                                    } else {
                                        print("Scanned code: \(qrresult)")
                                        
                                        Task {
                                            do {
                                                let webSocket = try await WebSocketProvider(url: ApplicationConfig.wssUrl + "/channel/\(qrresult)")
                                                print("WebSocket initialized successfully.")

                                                // Generate session ECDH KEX, for educational purposes only
                                                let kexM = generateEcdhKeyPair()
                                                
                                                // Wait for init message from web session
                                                let initMessage = try await webSocket.awaitForMessage(messageType: .message)
                                                let jsonInitMessageData = initMessage.data?.data(using: .utf8)
                                                let initMessageObj = try JSONDecoder().decode(PasskeyAuthInit.self, from: jsonInitMessageData!)

                                                
                                                /*
                                                 * We will as well send allow credID, because we want to enforce
                                                 * explicit experience
                                                 */
                                                let allowList = [try cdp.getFirstActivePasskey()!.cred_id!]
                                                let authChallenge = PasskeyAuthInitChallenge(
                                                    challenge: try generateRandomBytes(32).base64URLEncodedString(),
                                                    allowCredIds: allowList,
                                                    rpId: ApplicationConfig.rpId,
                                                    kexM: kexM.publicKey.base64URLEncodedString()
                                                )
                                                
                                                let authChallengeData = try JSONEncoder().encode(authChallenge)
                                                let authChallengeMsgWrapper = WSMessage(type: .message, data: String(data: authChallengeData, encoding: .utf8))
                                                
                                                try await webSocket.send(message: authChallengeMsgWrapper)
                                                
                                                // Waiting for attestation response
                                                let authResponse = try await webSocket.awaitForMessage(timeout: 30000, messageType: .message)

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
//                                                print("KEX", keyAgreement.withUnsafeBytes({ Data(Array($0)) }).map { String(format: "%02x", $0) }.joined())
                                                
                                                let sessionSecret = keyAgreement.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: try authChallenge.challenge.base64URLDecodedData(), outputByteCount: 32)
                                                                                                                                                
                                                let newToken = try generateRandomBytes(16)
                                                let encryptedToken = try encryptAesGcm(data: newToken, key: sessionSecret)
                                                print("Encrypted token: \(newToken.map { String(format: "%02x", $0) }.joined())")
                                                let ackMessage = PasskeyAck(encryptedAccessToken: encryptedToken.base64URLEncodedString())
                                                
                                                let ackMessageData = try JSONEncoder().encode(ackMessage)
                                                let ackMessageWrapper = WSMessage(type: .message, data: String(data: ackMessageData, encoding: .utf8))
                                                
                                                try await webSocket.send(message: ackMessageWrapper)
                                                
                                                let _ = try await webSocket.awaitForMessage(timeout: 30000, messageType: .message)

                                                try cdp.newSession(deviceName: initMessageObj.browserName, accessToken: Data(newToken).base64EncodedString())
                                                
                                                
                                                print("KEX Completed")
                                               
                                            } catch {
                                                print("Failed to initialize WebSocket: \(error)")
                                            }
                                        }
                                    }
//
//
                                } catch {
                                    print("Error")
                                    print(error)
                                }
                            }
                            .popover(isPresented: $wsIsProcessing) {
                                Text("Loading...")
                                    .padding()
                            }

                    }) {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundColor(.blue)
                            
                            Text("Add new device")
                                .foregroundStyle(.blue)
                        }
                        
                    }
                    
                    
                    if !sessions.isEmpty {
                        Button {
                            do {
                                try cdp.deleteAllSessions()
                                sessions = []
                            } catch {
                                print("Error")
                                print(error)
                            }
                            
                        } label: {
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                    .foregroundColor(.red)
                                
                                Text("Terminate all other sessions")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Load sessions
            sessions = try! cdp.fetchSessions()
        }
    }
        
}
