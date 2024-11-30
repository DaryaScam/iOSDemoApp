//
//  WebSocketPasskeys.swift
//  im-hybrid-demo
//
//  Created by Personal on 29/11/2024.
//
import Foundation

struct PasskeyAuthInit: Codable {
    let browserName: String
}

struct PasskeyAuthInitChallenge: Codable {
    let challenge: String
    let allowCredIds: [String]
    let rpId: String
    let kexM: String
}

struct PasskeyAuthResponse: Codable {
    let id: String
    let rawId: String
    let response: Response
    let type: String
    let clientExtensionResults: ClientExtensionResults?
    let authenticatorAttachment: String?
    
    struct Response: Codable {
        let authenticatorData: String
        let clientDataJSON: String
        let signature: String
        let userHandle: String
    }
    
    struct ClientExtensionResults: Codable {
        let credProps: CredProps?
    }
    
    struct CredProps: Codable {
        let rk: Bool?
    }
}

struct PasskeyAck: Codable {
    let encryptedAccessToken: String
}


enum PasskeyError: Error {
    case invalidChallenge(String)
    case invalidOrigin(String)
    case invalidOperation(String)
    case invalidSignature
}

struct AssertionValidationResult {
    let origin: String
    let challenge: String
    let newCounter: UInt32
}

// Generic passkey assertion validation function
// There is no challenge validation, because the challenge is validated in the WebSocket, as it contains some useful information
func verifyAuthenticatorResponse(authResp: PasskeyAuthResponse, cspasskey: CSPasskey, allowedOrigins: [String], expectedRpId: String) throws -> AssertionValidationResult {
    let clientDataData = try authResp.response.clientDataJSON.base64URLDecodedData()
    let clientDataHash = getSha256Digest(clientDataData)
    let clientData = try JSONDecoder().decode(ClientDataJSON.self, from: clientDataData)
    
    // Verify type
    if clientData.type != .get {
        throw PasskeyError.invalidOperation("Invalid operation type \(clientData.type). Expected \(WebAuthnOps.get)")
    }
    
    // Verify origin
    if !allowedOrigins.contains(clientData.origin) {
        throw PasskeyError.invalidOrigin("Origin \(clientData.origin) is not allowed. Must be one of \(allowedOrigins)")
    }

    // Verify AuthData
    let authDataBytes = try authResp.response.authenticatorData.base64URLDecodedData()
    let authData = try AuthData([UInt8](authDataBytes))
    
    let expectedRpIdHash = getSha256Digest(expectedRpId.data(using: .utf8)!)
    if authData.rpIdHash != expectedRpIdHash {
        throw PasskeyError.invalidOperation("Invalid rpIdHash")
    }
    
    if (authData.counter != 0 || cspasskey.counter != 0) && authData.counter <= cspasskey.counter {
        throw PasskeyError.invalidOperation("Invalid counter")
    }
    
    if authData.flags.userPresent != true || authData.flags.userVerified != true {
        throw PasskeyError.invalidOperation("User not present or verified")
    }
    
    // Verify signature
    let signatureBytes = try authResp.response.signature.base64URLDecodedData()
    let dataToVerify = authDataBytes + clientDataHash
    let publicKeyBytes = try cspasskey.public_key!.base64URLDecodedData()
    
    if try verifyES256Signature(derSignature: signatureBytes, data: dataToVerify, publicKey: publicKeyBytes) != true {
        throw PasskeyError.invalidSignature
    }
    
    return AssertionValidationResult(origin: clientData.origin, challenge: clientData.challenge, newCounter: authData.counter)
}
