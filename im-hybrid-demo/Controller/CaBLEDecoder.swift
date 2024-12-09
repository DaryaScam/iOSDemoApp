//
//  CaBLEDecoder.swift
//  im-hybrid-demo
//

import Foundation
import SwiftCBOR
import CryptoKit

// Sample: FIDO:/418562177955268225281332443023502268417513163403619432322081142933593775063859305339265481596723109276089304307252501220065513845467163047561829615534850109321447142660

// 41856217795526822
// 52813324430235022
// 68417513163403619
// 43232208114293359
// 37750638593053392
// 65481596723109276
// 08930430725250122
// 00655138454671630
// 47561829615534850
// 109321447142660

enum CborKeys: Int {
    case publicKey = 0
    case secret = 1
    case numberOfTunnels = 2
    case timestamp = 3
    case canDoStateAssistedTx = 4
    case mode = 5
}

let requiredKeys: [CborKeys] = [.publicKey, .secret, .numberOfTunnels, .mode]

enum HybridModes: String {
    case GetAssertion = "ga"
    case MakeCredential = "mc"
    case CredentialPresentation = "dcp"
    case CredentialIssuance = "dci"
}

struct HybridChallenge {
    let publicKey: [UInt8]
    let secret: [UInt8]
    let numberOfTunnels: UInt64
    let timestamp: UInt64
    let canDoStateAssistedTx: Bool
    let mode: HybridModes
}


enum CaBLEError: Error {
    case missingPrefix
    case failedToParseUint64
    case missingRequiredKey(String)
    case wrongFidoMode
    case badRequest
}


func DecodeChallengeBytesToStruct(_ challengeBytes: [UInt8]) throws -> HybridChallenge {
    do {
        let resultMap: [CborKeys: Any] = try decodeCborToMap(bytes: challengeBytes, keyType: CborKeys.self)
        for key in requiredKeys {
            if resultMap[key] == nil {
                throw CaBLEError.missingRequiredKey("Key \(key) is missing.")
            }
        }
        
        let pubKey = resultMap[.publicKey] as! [UInt8]
        let secret = resultMap[.secret] as! [UInt8]
        let numberOfTunnels = resultMap[.numberOfTunnels] as! UInt64
        let mode = HybridModes(rawValue: resultMap[.mode] as! String)!
        
        if pubKey.count != 33 || secret.count != 16 || numberOfTunnels < 0 || numberOfTunnels > 255 {
            throw CaBLEError.badRequest
        }
        
        if mode != .MakeCredential {
            throw CaBLEError.wrongFidoMode
        }
        
        let timestamp: UInt64 = resultMap[.timestamp] as? UInt64 ?? 0
        let canDoStateAssistedTx: Bool = resultMap[.canDoStateAssistedTx] as? Bool ?? false
        
        
        return HybridChallenge(
            publicKey: pubKey,
            secret: secret,
            numberOfTunnels: numberOfTunnels,
            timestamp: timestamp,
            canDoStateAssistedTx: canDoStateAssistedTx,
            mode: mode
        )
    } catch {
        throw error
    }
}

func DecodeCabLEChallenge(_ qrChallenge: String) throws -> HybridChallenge {
    if !qrChallenge.hasPrefix("FIDO:/") {
        throw CaBLEError.missingPrefix
    }
    
    let rawChallenge = qrChallenge.dropFirst(6)
    var rawBuffer: [UInt8] = []
    let chunkSize = 17
    
    let chunks = stride(from: 0, to: rawChallenge.count, by: chunkSize).map {
        let start = rawChallenge.index(rawChallenge.startIndex, offsetBy: $0)
        let end = rawChallenge.index(start, offsetBy: chunkSize, limitedBy: rawChallenge.endIndex) ?? rawChallenge.endIndex
        return String(rawChallenge[start..<end])
    }
    
    for rawChunk in chunks {
        guard let u64num = UInt64(rawChunk) else {
            throw CaBLEError.failedToParseUint64
        }
        
        let u64buff = withUnsafeBytes(of: u64num.littleEndian) { Data($0) }

        var buffClean: [UInt8] = []
        var isPadding = true
        // Reverse to trim 0x00 end padding
        for beByte in u64buff.reversed() {
            if isPadding && beByte == 0 {
                continue
            } else {
                isPadding = false
                buffClean.insert(beByte, at: 0)
            }
        }
                
        rawBuffer = rawBuffer + buffClean
    }
    
    print(rawBuffer.map { String(format: "%02x", $0) }.joined())
    do {
        return try DecodeChallengeBytesToStruct(rawBuffer)
    } catch {
        print(error)
        throw error
    }
}

enum HybridKeyPurposes: UInt8 {
    case keyPurposeEIDKey = 0x01
    case keyPurposeTunnelID = 0x02
    case keyPurposePSK = 0x03
}

func GenerateAdvertisingData(_ hybridChallenge: HybridChallenge) throws -> [UInt8] {
    let secretSymkey = SymmetricKey(data: hybridChallenge.secret)
    let eidKey: SymmetricKey = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: secretSymkey,
        salt: Data(),
        info: Data([HybridKeyPurposes.keyPurposeEIDKey.rawValue]),
        outputByteCount: 64
    )
    let rawEidKey = eidKey.withUnsafeBytes { Data(Array($0)) }
    
    do {
        // Generate payload

        let connectionNonce = try generateRandomBytes(10)
        let routingId = try generateRandomBytes(3)
        let tunnelId: UInt16 = 1
        
        let payload: [UInt8] = [0x00] + connectionNonce + routingId + [UInt8(tunnelId & 0xff), UInt8(tunnelId >> 8)]
        
        let encrypted = try encryptBlock(data: Data(payload), key: Data(rawEidKey[..<32]))
        
        let mac = HMAC<SHA256>.authenticationCode(for: encrypted, using: SymmetricKey(data: Data(rawEidKey.dropFirst(32))))
        let macRaw = mac.withUnsafeBytes { Array($0) }
        
        return Array(encrypted) + macRaw[0...4]
    } catch {
        throw error
    }
}
