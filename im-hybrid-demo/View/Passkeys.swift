//
//  Passkeys.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

import SwiftUI
import CoreData



struct ManagePasskeys: View {
    private var passkeyscontroller = PasskeysController()
    private var cdp = try? CoreDataProvider()

    @State private var registerPasskey: CSPasskey? = nil
    
    @State private var showError = false
    @State private var flowError: Error? = nil
    
    func getAnchor() -> UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
    }
    
    var body: some View {
        VStack {
            if registerPasskey == nil {
                HStack {
                    Image(systemName: "person.badge.key.fill")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .foregroundColor(.blue)
                    
                    Text("Secure your account with passkey")
                        .font(.title2)
                }
                
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .padding(10)
                    
                    Text("Passkey allows you to log back in, fast, and securely")
                    
                    Spacer()
                }
                .padding(.top, 20)
                
                HStack {
                    Image(systemName: "faceid")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .padding(10)
                
                    Text("User your passkey with faceid, touychid, or pin")
                    
                    Spacer()
                }
                .padding(.top, 20)
                
                HStack {
                    Image(systemName: "person.icloud.fill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .padding(10)
                    
                    Text("Your passkey is stored, and synced across all devices")
                    
                    Spacer()
                }
                .padding(.top, 20)
                                
                Button {
                    
                    do {
                        let anchor = getAnchor()
                        let user = try self.cdp!.getUser()!
                        let challenge = try generateRandomBytes(32)
                                            
                        if anchor != nil {
                            passkeyscontroller.createPasskey(userName: user.name!, challenge: Data(challenge), userID: user.uuid!.getData(), anchor: getAnchor()!) {
                                result in
                                switch result {
                                case .success:
                                    do {
                                        print("Passkey registered successfully")
                                        let attPasskeyInfo = try result.get()
                                        registerPasskey = try cdp!.newPasskey(credId: attPasskeyInfo.id, counter: Int32(attPasskeyInfo.counter), publicKeyB64Url: attPasskeyInfo.publicKey, aaguid: attPasskeyInfo.aaguid)
                                    } catch {
                                        flowError = error
                                        showError = true
                                    }
                                case .failure(let error):
                                    flowError = error
                                    showError = true
                                }
                            }
                        } else {
                            flowError = PasskeyError.noKeyWindowsAvailable("No key windows available")
                            showError = true
                        }
                    } catch {
                        flowError = error
                        showError = true
                    }
                   
                } label: {
                    Image(systemName: "person.badge.key.fill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .foregroundColor(.white)
                        .padding(10)
                    
                    Text("Setup passkey")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                }
                .tint(.blue)
                .buttonStyle(.borderedProminent)
                .padding()
                .alert("Error registering passkey", isPresented: $showError) {
                    if let error = flowError {
                        Text(error.localizedDescription)
                    } else {
                        Text("Unknown error")
                    }
                    
                    Button("OK", role: .cancel) {
                        flowError = nil
                        showError = false
                    }
                }

            } else {
                HStack {
                    Image(systemName: "person.badge.key.fill")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .foregroundColor(.blue)
                    
                    Text("Manage your passkey")
                        .font(.title2)
                }
                
                Text("Your account is protected with passkey. This allows you to securely log into the app, and in the browser. Learn more here")
                
                List{
                    VStack {
                        HStack {
                            Image(systemName: "faceid")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .padding(10)
                            
                            VStack(alignment: .leading) {
                                Text("Passkey on iOS")
                                    .font(.title3)
                                
                                Text("Registered on \(localizedDateTimeString(from: registerPasskey!.created_at!))")
                                    .font(.caption)
                            }
                            
                        }
                        
                        Button("Remove passkey") {
                            do {
                                registerPasskey?.is_disabled = true
                                try cdp!.updatePasskey(passkey: registerPasskey!)
                                registerPasskey = nil
                            } catch {
                                flowError = error
                                showError = true
                            }
                        }
                    }
                }

            }
        }
        .padding(20)
        .onAppear {
            do {
                registerPasskey = try cdp!.getFirstActivePasskey()
            } catch {
                flowError = error
                showError = true
            }
        }
    }
}

