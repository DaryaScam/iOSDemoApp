//
//  CableV2.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//
//  Based on Chromium CableV2 implementation <https://github.com/chromium/chromium/blob/40055eac50481c331106f9034b5cda16682b048f/device/fido/cable/v2_handshake.cc#L979>
//

import Foundation
import CryptoKit

enum CableV2Error: Error {
    case invalidKeyLength(String)
    case invalidX962PointLength(String)
    case unsupportedProtocolName
    case failedToDecrypt(String)
    case badInitMessage(String)
}

class CableV2 {
    private var ns: Noise? = nil
    
    private var clientToPlatformKey: Data? = nil
    private var platformToClientKey: Data? = nil
    private var clientToPlatformSEQ: UInt32 = 0
    private var platformToClientSEQ: UInt32 = 0
    
    func decryptHandshake(psk: Data?, qrKeyX962: Data, initMsg: Data) throws -> (plaintext: Data, peerESKey: (publicKey: Data, privateKey: P256.KeyAgreement.PrivateKey), reqESX962: Data) {
//        guard psk != nil || peerPub != nil else {
//            throw CableV2Error.invalidKeyLength("Must have psk or peer public key")
//        }
        
        if initMsg.count < kP256X962Length {
            throw CableV2Error.badInitMessage("Invalid message length")
        }
        
        let reqESX962 = initMsg.subdata(in: 0..<kP256X962Length)
        let ciphertext = initMsg.subdata(in: kP256X962Length..<initMsg.count)
        
        var prologue: UInt8 = 0x00
        
        // Only PSK KN flow for now
        self.ns = try Noise(.KN)
        prologue = 0x01
        self.ns!.mixHash(Data([prologue]))
        try self.ns!.mixHashPoint(qrKeyX962) // Assuming x962Key is privateKey for now
        try self.ns!.mixKeyAndHash(psk!)
    
        self.ns!.mixHash(reqESX962)
        try self.ns!.mixKey(reqESX962)
        
//        if let peerPub = peerPub {
//            let sharedESP = try deriveECDHSharedSecret(privateKey: ephemeral.privateKey, publicKey: peerPub)
//            ns.mixKey(sharedESP.withUnsafeBytes({ Data($0) }))
//        }
        
        let plaintext = self.ns!.decryptAndHash(ciphertext)
        if plaintext == nil {
            throw CableV2Error.failedToDecrypt("Failed to decrypt")
        }
        
        let resEphemeral = generateEcdhKeyPair()

        return (plaintext: plaintext!, peerESKey: resEphemeral, reqESX962: reqESX962)
        
    }
    
    func generateHandshakeAck(peerESKey: P256.KeyAgreement.PrivateKey, reqESX962: Data) throws -> (handhshakeAck: Data, handshakeHash: Data) {
        self.ns!.mixHash(peerESKey.publicKey.x963Representation)
        try self.ns!.mixKey(peerESKey.publicKey.x963Representation)
        try self.ns!.mixKey(deriveECDHSharedSecret(privateKey: peerESKey, publicKey: reqESX962).data)
        
        let ciphertext = try self.ns!.encryptAndHash(generateRandomBytes(32))
        
        let trafficKeys = self.ns!.getTrafficKeys()
        self.clientToPlatformKey = trafficKeys.o1
        self.platformToClientKey = trafficKeys.o2
        
        return (handhshakeAck: peerESKey.publicKey.x963Representation + ciphertext, handshakeHash: self.ns!.handshakeHash)
    }
    
    func encryptToPlatform(data: Data) throws -> Data {
    }
}
