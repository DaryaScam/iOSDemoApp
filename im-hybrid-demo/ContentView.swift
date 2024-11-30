//
//  ContentView.swift
//  im-hybrid-demo
//

import SwiftUI
import CryptoKit

enum SettingMenus: String {
    case devices = "Devices"
    case about = "About"
}



var navigationLinks: [SettingMenus] = [.devices, .about]

struct ContentView: View {
    @State private var path = [String]()
    @State private var selectedTab: String = "settings"
    private var cdp = try? CoreDataProvider()

    var body: some View {
        TabView(selection: $selectedTab) {
            // Messages
            VStack {
                HStack {
                    Text("Messages")
                        .font(.title)
                        .bold()
                        
                }
                
                List {
                    ChatBox(name: "John Doe", message: "Hey, how are you?")
                                        
                    ChatBox(name: "Mark Cucumberg", message: "Your pet lizard is very cute!")
                    
                }
            }.tabItem {
                Image(systemName: "message")
                Text("Messages")
            }.tag("messages")
            
            // Settings
            VStack {
                VStack {
                    ZStack {
                        Circle()
                            .fill(Color.blue) // Background color of the circle
                            .frame(width: 70, height: 70) // Circle size
                        
                        Text("JD")
                            .font(.largeTitle) // Font size for the text
                            .fontWeight(.bold)
                            .foregroundColor(.white) // Text color
                    }
                    Text("John Doe")
                        .font(.title)
                        .bold()
                    Text("+1 234 5567 8890 @johnydoey")
                }
                .padding([.bottom], 20)
                
                NavigationStack {
                    List{
                        NavigationLink(destination: {
                            QRDevicesRegisterView()
                        }) {
                            Text("Devices")
                        }
                        
                        NavigationLink(destination: {
                            ManagePasskeys()
                        }) {
                            Text("Passkeys")
                            
                        }
                        Button("Test Decoding") {
                            do {
                                let payload = "{\"id\":\"sXS-4Qi-Fvn-AcayS8MIKJWPTCw\",\"rawId\":\"sXS-4Qi-Fvn-AcayS8MIKJWPTCw\",\"response\":{\"authenticatorData\":\"pnV2RcjM5pHVO-0YZnQPe6IiMxie4aPT3koQNOcccpAdAAAAAA\",\"clientDataJSON\":\"eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiTVdGcE16UnJPVGRuVkVack4ySXhPV0pEYUhwemFtSk1PV2N5VXpKaU1FbDFUekJMYUZOeExYWnFVUzVDVUVWNVdERTVVbXhPZVUxc1ltUk1ialY1TTNCemJWbHlRVkpVVm5ZMlNGcHFZVlJpZEZaZmIwRjVkVVJ3YlhWbGNWTnBMVlV6WHpjMldIUklWakExTlZaWVptaDViVFZxTm1vMFNVTXpUbVU0UkRaT01tYyIsIm9yaWdpbiI6Imh0dHBzOi8vd2ViLmRhcnlhc2NhbS5pbmZvIiwiY3Jvc3NPcmlnaW4iOmZhbHNlLCJvdGhlcl9rZXlzX2Nhbl9iZV9hZGRlZF9oZXJlIjoiZG8gbm90IGNvbXBhcmUgY2xpZW50RGF0YUpTT04gYWdhaW5zdCBhIHRlbXBsYXRlLiBTZWUgaHR0cHM6Ly9nb28uZ2wveWFiUGV4In0\",\"signature\":\"MEQCIBVg_dRJWWB6dv6l0x32ocHW7asf6HllcM1-JUENkVJnAiBtag7q9HA9DPBLVWPMOjTILhNvBZ7KEmBLSxu9-Oh2gw\",\"userHandle\":\"UllrnLPsTFebYsOU5hn7kQ\"},\"type\":\"public-key\",\"clientExtensionResults\":{},\"authenticatorAttachment\":\"platform\"}"
                                let authResponseObj = try! JSONDecoder().decode(PasskeyAuthResponse.self, from: payload.data(using: .utf8)!)
                               
                                let passkeys = try cdp!.fetchPasskeys()
                                print("Passkeys: \(passkeys)")
                                
                                // Verify the response
                                let result = try verifyAuthenticatorResponse(
                                    authResp: authResponseObj,
                                    cspasskey: cdp!.getFirstActivePasskey()!,
                                    allowedOrigins: ApplicationConfig.allowedOrigins,
                                    expectedRpId: ApplicationConfig.rpId
                                )
                                
                                print("Verification result: \(result)")
                                
                                
                                let decodedChallenge = try result.challenge.base64URLDecodedString()
                                let challengeParts = decodedChallenge.split(separator: ".")
                                if challengeParts.count != 2 {
                                    throw PasskeyError.invalidChallenge("Challenge has invalid format. Expected challenge.kexc")
                                }
                                
                                let originalChallenge = "1ai34k97gTFk7b19bChzsjbL9g2S2b0IuO0KhSq-vjQ"
                                print("Challenge: \(challengeParts)")
                                
//                                if challengeParts[0] != authChallenge.challenge {
//                                    throw PasskeyError.invalidChallenge("Challenge does not match the expected challenge")
//                                }
//                                
                                let kexC = challengeParts[1]
                                let kexCData = try String(kexC).base64URLDecodedData()
                                
                                print("KEX C: \(kexCData.map { String(format: "%02x", $0) }.joined())")
                                
                                // Generate the shared secret
                                
                                let kexM = generateEcdhKeyPair()
                                
                                let keyAgreement = try kexM.privateKey.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: kexCData))
                                
                                let sessionSecret = keyAgreement.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: try originalChallenge.base64URLDecodedData(), outputByteCount: 32)
                                let sessionSecretBytes = sessionSecret.withUnsafeBytes { Data(Array($0)) }
                                
                                print("Shared secret: \(sessionSecret) \(sessionSecret.withUnsafeBytes { Data(Array($0)) }.map { String(format: "%02x", $0) }.joined())")
                                
                                let newToken = try generateRandomBytes(16)
                                print("New token: \(newToken.map { String(format: "%02x", $0) }.joined())")
                                
                                let encryptedToken = try encryptBlock(data: newToken, key: sessionSecretBytes)
                                print("Encrypted token: \(encryptedToken.map { String(format: "%02x", $0) }.joined())")
                                
                            
                                
                                
                                
                                
                            } catch {
                                print("Failed to validate payload: \(error)")
                            }
                        }
                    }
                }

                
               
            }.tabItem {
                Image(systemName: "gear")
                Text("Settings")
            }.tag("settings")
        }
    }
}

#Preview {
    ContentView()
}
//
