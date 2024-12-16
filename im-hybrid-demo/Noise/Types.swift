//
//  Types.swift
//  im-hybrid-demo
//
//  Created by Personal on 15/12/2024.
//

import Foundation

/* ---------------------------------------------------------------- *
 * TYPES                                                            *
 * ---------------------------------------------------------------- */

struct Keypair {
    var publicKey: Data
    var privateKey: Data
}

struct MessageBuffer {
    var ne: Data
    var ns: Data
    var ciphertext: Data
}

struct CipherState {
    var k: Data
    var n: UInt64
}

struct SymmetricState {
    var cs: CipherState
    var ck: Data
    var h: Data
}

struct HandshakeState {
    var ss: SymmetricState
    var s: Keypair
    var e: Keypair
    var rs: Data
    var re: Data
    var psk: Data
}

struct NoiseSession {
    var hs: HandshakeState
    var h: Data
    var cs1: CipherState
    var cs2: CipherState
    var mc: UInt64
    var i: Bool
}

struct HKDF3Output {
    var o1: Data
    var o2: Data
    var o3: Data
}
