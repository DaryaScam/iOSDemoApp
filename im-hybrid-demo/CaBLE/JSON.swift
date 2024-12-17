//
//  JSON.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

import Foundation


struct AuthTokenRequestInit: Codable {
    let handshakeHashHex: String
    let os: String
}

struct AuthTokenResult: Codable {
    let token: String
}
