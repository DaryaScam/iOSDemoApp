//
//  ContentView.swift
//  im-hybrid-demo
//

import SwiftUI

enum SettingMenus: String {
    case devices = "Devices"
    case about = "About"
}

var navigationLinks: [SettingMenus] = [.devices, .about]

struct ContentView: View {
    @State private var path = [String]()
    @State private var selectedTab: String = "settings"
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
                            .frame(width: 100, height: 100) // Circle size
                        
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
                            QRDeviceRegisterView()
                        }) {
                            Text("Devices")
                        }
                        
                        NavigationLink(destination: {
                            ManagePasskeys()
                        }) {
                            Text("Passkeys")
                            
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
