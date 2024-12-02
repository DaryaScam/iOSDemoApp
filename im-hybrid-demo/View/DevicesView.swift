//
//  DevicesView.swift
//  im-hybrid-demo
//
//  Created by Personal on 02/12/2024.
//

import SwiftUI
import CryptoKit

struct DevicesView: View {

    private var cdp: CoreDataProvider = try! CoreDataProvider()
    @State private var sessions: [CSSession] = []

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
                    
                    
                    NavigationLink(destination: QRDevicesRegisterView()) {
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
