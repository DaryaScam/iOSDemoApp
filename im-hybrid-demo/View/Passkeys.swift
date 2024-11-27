//
//  Passkeys.swift
//  im-hybrid-demo
//

import SwiftUI

struct ManagePasskeys: View {
    private var passkeyscontroller = PasskeysController()
    
    var body: some View {
        VStack {
            Text("Existing Passkeys")
                .font(.title)
            
            List{
                Text("No passkeys registered")
                    .font(.title3)
                    
                Button("Register passkey") {
                    if let anchor = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .flatMap({ $0.windows })
                        .first(where: { $0.isKeyWindow }) {
                        passkeyscontroller.signUpWith(userName: "test", anchor: anchor)
                    } else {
                        print("No key window found")
                    }
                }
                
                Button("TestParseAuthData") {
                    do {
                        let authdata = "a6757645c8cce691d53bed1866740f7ba22233189ee1a3d3de4a1034e71c72905d00000000fbfc3007154e4ecc8c0b6e020557d7bd00143b5697e89a870c646d0407ce01abfdf646a114faa50102032620012158205772991b9c9f63dc08b8a1bfe358f138942dbb65fc2e0fee58f25263d8fb9c67225820887bb569206d7ed29a44185efaaeddd478b6d0f3e3b06385110933e2f77379e5"
                        let authdataBytes = try hexToBytes(authdata)
                        let parsedAuthData = try AuthData(authdataBytes)
                        let publicKey = try parsedAuthData.getX962PublicKey()
                        
                        
                    } catch {
                        print("Error")
                        print(error)
                    }
                    
                }
            }
            
        }
    }
}

