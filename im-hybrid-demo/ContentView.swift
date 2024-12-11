//
//  ContentView.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

import SwiftUI
import CryptoKit
import Foundation

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
                    ChatBox(name: "Jane Doe", message: "Hey, how are you?")
                                        
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
                            DevicesView()
                        }) {
                            Text("Devices")
                        }
                        
                        NavigationLink(destination: {
                            ManagePasskeys()
                        }) {
                            Text("Passkeys")
                            
                        }
                        Button("TestDecode") {
                            do {
                                let payloadHex = "a6005821034de59e86ee40a6ddf569fb6ebf5e94b33576b5c95feec0629f0b87902b260764015050d7aaaaa247c4b5e7bf37fc5e7cf4b00201031a6754ccde04f405626761"
                                
                                let challengeBytes = try payloadHex.decodeHex()
                                let resultMap: [CborKeys: Any] = try decodeCborToMap(bytes: challengeBytes, keyType: CborKeys.self)
                                print(resultMap)
                            } catch {
                                print("Error")
                                print(error)
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
