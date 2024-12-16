//
//  CableV2.swift
//  im-hybrid-demo
//
//  Created by Personal on 15/12/2024.
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
    private var noiseSession: Noise? = nil
    
    func decryptInitConnectMessage(psk: Data?, qrKeyX962: Data, initMsg: Data) throws -> (plaintext: Data, ephemeralKey: (publicKey: Data, privateKey: P256.KeyAgreement.PrivateKey)) {
//        guard psk != nil || peerPub != nil else {
//            throw CableV2Error.invalidKeyLength("Must have psk or peer public key")
//        }
        
        if initMsg.count < kP256X962Length {
            throw CableV2Error.badInitMessage("Invalid message length")
        }
        
        let reqESX962 = initMsg.subdata(in: 0..<kP256X962Length)
        let ciphertext = initMsg.subdata(in: kP256X962Length..<initMsg.count)
        
        var prologue: UInt8 = 0x00
        let ns: Noise
        
        
        // Only PSK KN flow for now
        ns = try Noise(.KN)
        prologue = 0x01
        ns.mixHash(Data([prologue]))
        try ns.mixHashPoint(qrKeyX962) // Assuming x962Key is privateKey for now
        try ns.mixKeyAndHash(psk!)
    
        ns.mixHash(reqESX962)
        try ns.mixKey(reqESX962)
        
//        if let peerPub = peerPub {
//            let sharedESP = try deriveECDHSharedSecret(privateKey: ephemeral.privateKey, publicKey: peerPub)
//            ns.mixKey(sharedESP.withUnsafeBytes({ Data($0) }))
//        }
        
        let plaintext = ns.decryptAndHash(ciphertext)
        if plaintext == nil {
            throw CableV2Error.failedToDecrypt("Failed to decrypt")
        }
        
        let resEphemeral = generateEcdhKeyPair()

        return (plaintext: plaintext!, ephemeralKey: resEphemeral)
        
    }
}
