//
//  CaBLEDecoder.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
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
    case NonStandardToken = "nst"
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
        
        
        // To avoid collisions with FIDO
        // But this can be anything
        if mode != .NonStandardToken {
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

enum HybridKeyPurposes: UInt32 {
    case keyPurposeEIDKey = 0x01
    case keyPurposeTunnelID = 0x02
    case keyPurposePSK = 0x03
}

func HybridHDKFDerive(inputKey: Data, purpose: HybridKeyPurposes, outputByteCount: Int) -> Data {
    let secretSymkey = SymmetricKey(data: inputKey)
    let derived: SymmetricKey = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: secretSymkey,
        salt: Data(),
        info: purpose.rawValue.dataLE,
        outputByteCount: outputByteCount
    )
    
    return derived.withUnsafeBytes { Data(Array($0)) }
}

func GenerateHybridTunnelUrl(hybridChallenge: HybridChallenge, routingId: Data, selectedDomain: CableDomain) throws -> String {
    let tunnelId = HybridHDKFDerive(inputKey: Data(hybridChallenge.secret), purpose: .keyPurposeTunnelID, outputByteCount: 16)
    return "wss://\(selectedDomain.domain)/cable/connect/\(routingId.encodeToHex())/\(tunnelId.encodeToHex())"
}


struct AdvertisingData {
    let connectionNonce: Data
    let routingId: Data
    let serviceData: Data
}

func GenerateAdvertisingData(hybridChallenge: HybridChallenge, tunnelId: CableDomain) throws -> AdvertisingData {
    let rawEidKey = HybridHDKFDerive(inputKey: Data(hybridChallenge.secret), purpose: .keyPurposeEIDKey, outputByteCount: 64)
    let encryptionKey = rawEidKey.prefix(32)
    let macKey = rawEidKey.dropFirst(32)
        
    do {
        // Generate payload
        let connectionNonce = try generateRandomBytes(10)
        let routingId = try generateRandomBytes(3)
        
        let payload: [UInt8] = [0x00] + connectionNonce + routingId + tunnelId.uint16DataLE
        
        let encrypted = try encryptBlock(data: Data(payload), key: encryptionKey)
        
        let mac = HMAC<SHA256>.authenticationCode(for: encrypted, using: SymmetricKey(data: macKey))
        let macRaw = mac.withUnsafeBytes { Array($0) }
        let advertisignRawData = encrypted + macRaw[0..<4]
        
        return AdvertisingData(connectionNonce: connectionNonce, routingId: routingId, serviceData: advertisignRawData)
    } catch {
        throw error
    }
}

enum CableDomain: Int {
    case d0000_ua5v = 0x00
    case d0001_auth = 0x01
    case d0269_dljqskoal33ac = 0x010d

    var domain: String {
        switch self {
        case .d0000_ua5v:
            return "cable.ua5v.com"
        case .d0001_auth:
            return "cable.auth.com"
        case .d0269_dljqskoal33ac:
            return "cable.dljqskoal33ac.org"
        }
    }
    
    var uint16DataLE: Data {
        return Data([UInt8(self.rawValue & 0xff), UInt8(self.rawValue >> 8)])
    }
}
