//
//  Config.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
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
