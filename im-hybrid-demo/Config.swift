//
//  Config.swift
//  im-hybrid-demo
//
//  Created by Personal on 30/11/2024.
//

struct AppConfig {
    let rpId: String
    let allowedOrigins: [String]
    
    let wssUrl: String
}

let ApplicationConfig = AppConfig(
    rpId: "web.daryascam.info",
    allowedOrigins: ["https://web.daryascam.info"],
    wssUrl: "wss://ws.daryascam.info"
)
