//
//  Noise.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//
//  Based on Noise Protocol Framework <https://noiseprotocol.org>
//  Reference source code used is Chromium's Noise Protocol Implementation <https://github.com/chromium/chromium/blob/3ea88b4b3ad399f0fa45c96894eb70dbc5477b10/device/fido/cable/noise.cc>
//

import Foundation
import CryptoKit

/* ---------------------------------------------------------------- *
 * CONSTANTS                                                        *
 * ---------------------------------------------------------------- */

let emptyKey = Data(repeating: 0, count: 32)
let minNonce: UInt64 = 0

enum NoiseProtocol: String {
    case KN = "Noise_KNpsk0_P256_AESGCM_SHA256"
    case NK = "Noise_NKpsk0_P256_AESGCM_SHA256"
    case NKNoPsk = "Noise_NK_P256_AESGCM_SHA256"
    
    var data: Data {
        return self.rawValue.data(using: .utf8)!
    }
}

let kP256X962Length = 1 + 32 + 32

/* ---------------------------------------------------------------- *
 * PROCESS                                                          *
 * ---------------------------------------------------------------- */

enum NoiseError: Error {
    case invalidKeyLength
    case invalidX962PointLength
    case unsupportedProtocolName
}

class Noise {
    var chainingKey: Data
    var h: Data
    var symmetricKey: Data
    var symmetricNonce: UInt32

    init(_ protocolName: NoiseProtocol) throws {
        self.chainingKey = Data(repeating: 0, count: 32)
        self.h = Data(repeating: 0, count: 32)
        self.symmetricKey = Data(repeating: 0, count: 32)
        self.symmetricNonce = 0
        self.chainingKey.replaceSubrange(0..<protocolName.data.count, with: protocolName.data)

        self.h = self.chainingKey
    }

    func mixHash(_ data: Data) {
        self.h = Data(getSha256Digest(self.h + data))
    }

    func mixKey(_ ikm: Data) throws {
        let hkdf2out = HKDF3(ck: self.chainingKey, ikm: ikm)
        self.chainingKey = hkdf2out.o1
        try self.initializeKey(hkdf2out.o2)
    }

    func mixKeyAndHash(_ ikm: Data) throws {
        let hkdf2out = HKDF3(ck: self.chainingKey, ikm: ikm)
        self.chainingKey = hkdf2out.o1
        self.mixHash(hkdf2out.o2)
        try self.initializeKey(hkdf2out.o3)
    }
    
    func initializeKey(_ key: Data) throws {
        guard key.count == 32 else {
            throw NoiseError.invalidKeyLength
        }

        self.symmetricKey = key
        self.symmetricNonce = 0
    }

    func getTrafficKeys() -> HKDF3Output {
        return HKDF3(ck: self.chainingKey, ikm: Data())
    }

    // Encryption
    func encryptAndHash(_ plaintext: Data) -> Data {
        let nonce = self.getAndIncrementSymmetricNonce()
        let cipher = try! AES.GCM.seal(plaintext, using: SymmetricKey(data: self.symmetricKey), nonce: AES.GCM.Nonce(data: nonce), authenticating: self.h)
        let ciphertext = cipher.ciphertext + cipher.tag

        self.mixHash(ciphertext)
        return ciphertext
    }

    func decryptAndHash(_ ciphertext: Data) -> Data? {
        let nonce = self.getAndIncrementSymmetricNonce()
        
        let tag = ciphertext.suffix(16)
        let encryptedData = ciphertext.prefix(ciphertext.count - 16)

        do {
            let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: encryptedData, tag: tag)
            let plaintext = try AES.GCM.open(sealedBox, using: SymmetricKey(data: self.symmetricKey), authenticating: self.h)

            self.mixHash(ciphertext)

            return plaintext
        } catch {
            print("Error noise decryption: \(error)")
            return nil
        }
    }

    func mixHashPoint(_ x962Point: Data) throws {
        guard x962Point.count == kP256X962Length else {
            throw NoiseError.invalidX962PointLength
        }

        self.mixHash(x962Point)
    }

    // Utility
    func getAndIncrementSymmetricNonce() -> Data {
        var nonce = Data(repeating: 0, count: 12) // 12-byte nonce initialized to zeros
        let bigEndianNonce = withUnsafeBytes(of: self.symmetricNonce.bigEndian) { Data($0) }
        nonce.replaceSubrange(0..<4, with: bigEndianNonce.prefix(4))
        
        return nonce
    }
    
    var handshakeHash: Data {
        return self.h
    }
}

