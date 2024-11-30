//
//  CTAP.swift
//  im-hybrid-demo
//
//  Created by Personal on 30/11/2024.
//

import Foundation

enum CtapClientAttKeys: String {
    case fmt = "fmt"
    case authData = "authData"
    case attStmt = "attStmt"
}

enum CoseKeys: Int {
    case kty = 1
    case alg = 3
    case crvOrN = -1
    case xOrE = -2
    case y = -3
}

enum CoseAlgs: Int {
    case es256 = -7
    case rs256 = -257
}

struct AuthDataFlags {
    let userPresent: Bool
    let userVerified: Bool
    let attestedDataIncluded: Bool
    let extensionDataIncluded: Bool
    let backupEligible: Bool
    let backupState: Bool
    
    init(_ flags: UInt8) {
        userPresent = flags & 0x01 != 0 // BIT 0
        userVerified = flags & 0x04 != 0 // BIT 2
        backupEligible = flags & 0x08 != 0 // BIT 3
        backupState = flags & 0x10 != 0 // BIT 4
        attestedDataIncluded = flags & 0x40 != 0 // BIT 6
        extensionDataIncluded = flags & 0x80 != 0 // BIT 7
    }
}

struct AuthData {
    let rpIdHash: [UInt8]
    let flags: AuthDataFlags
    let counter: UInt32
    
    let credentialID: [UInt8]?
    let aaguid: UUID?
    let credentialPublicKey: [UInt8]?
    
    enum AuthDataError: Error {
        case insufficientData(String)
        case invalidCredentialIDLength(String)
        case missingPublicKey
        case unsupportedAlgorithm(String)
        case invalidPublicKey(String)
    }
    
    init(_ authData: [UInt8]) throws {
        guard authData.count >= 37 else {
            throw AuthDataError.insufficientData("AuthData must be at least 37 bytes long.")
        }
        
        rpIdHash = Array(authData[0..<32])
        flags = AuthDataFlags(authData[32])
        counter = Data(authData[33..<37]).withUnsafeBytes { $0.load(as: UInt32.self) }
        
        var contData = Array(authData[37...])
        
        // Parse optional fields if `attestedCredentialData` flag is set
        if flags.attestedDataIncluded {
            // Ensure there is enough data for AAGUID and at least 2 bytes for credID length
            guard contData.count >= 18 else {
                throw AuthDataError.insufficientData("Not enough data for AAGUID and credential ID length.")
            }
            
            // AAGUID is 16 bytes
            let aaguidBytes = Array(contData[0..<16])
            aaguid = UUID(uuid: try uint8ArrayToUUIDT(aaguidBytes))
            contData = Array(contData[16...])
            
            // Credential ID length is 2 bytes
            let credIDLen = Int(contData[0] << 8 | contData[1])
            contData = Array(contData[2...])
            
            // Ensure there is enough data for the credential ID
            guard contData.count >= credIDLen else {
                throw AuthDataError.invalidCredentialIDLength("Not enough data for credential ID of length \(credIDLen).")
            }
            
            // Credential ID is `credIDLen` bytes
            credentialID = Array(contData[0..<credIDLen])
            contData = Array(contData[credIDLen...])
            
            // Credential public key is the rest of the data
            credentialPublicKey = contData
        } else {
            // If attestedCredentialData flag is not set, optional fields are nil
            aaguid = nil
            credentialID = nil
            credentialPublicKey = nil
        }
    }
    
    func getX962PublicKey() throws -> [UInt8] {
        if !flags.attestedDataIncluded || credentialPublicKey == nil {
            throw AuthDataError.missingPublicKey
        }
        
        let cborKeyMap = try decodeCborToMap(bytes: credentialPublicKey!, keyType: CoseKeys.self)
        
        let alg = cborKeyMap[CoseKeys.alg] as! Int
        if alg != CoseAlgs.es256.rawValue {
            throw AuthDataError.unsupportedAlgorithm("Unsupported algorithm: \(alg). Only ES256 is supported.")
        }
        
        let x = cborKeyMap[CoseKeys.xOrE] as! [UInt8]
        let y = cborKeyMap[CoseKeys.y] as! [UInt8]
        
        if x.count != 32 || y.count != 32 {
            throw AuthDataError.invalidPublicKey("Invalid public key length.")
        }
        
        return [0x04] + x + y
    }
}

enum WebAuthnOps: String, Codable {
    case get = "webauthn.get"
    case create = "webauthn.create"
}

struct ClientDataJSON: Codable {
    let type: WebAuthnOps
    let challenge: String
    let origin: String
    let crossOrigin: Bool?
    let tokenBinding: String?
}
