//
//  PasskeysController.swift
//  im-hybrid-demo
//


import AuthenticationServices
import Foundation
import os
import SwiftCBOR

// Truthfully stolen from https://docs-assets.developer.apple.com/published/0dc46a3bfa/ConnectingToAServiceWithPasskeys.zip
// https://web.daryascam.info/.well-known/apple-app-site-association

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

enum PasskeysControllerError: Error {
    case missingAuthData
    case missingPublicKey
    case invalidPublicKey(String)
    case unsupportedAlgorithm(String)
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
    let aaguid: String?
    let credentialPublicKey: [UInt8]?
    
    enum AuthDataError: Error {
        case insufficientData(String)
        case invalidCredentialIDLength(String)
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
            aaguid = aaguidBytes.map { String(format: "%02x", $0) }.joined()
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
            throw PasskeysControllerError.missingPublicKey
        }
        
        let cborKeyMap = try decodeCborToMap(bytes: credentialPublicKey!, keyType: CoseKeys.self)
        
        let alg = cborKeyMap[CoseKeys.alg] as! Int
        if alg != CoseAlgs.es256.rawValue {
            throw PasskeysControllerError.unsupportedAlgorithm("Unsupported algorithm: \(alg). Only ES256 is supported.")
        }
        
        let x = cborKeyMap[CoseKeys.xOrE] as! [UInt8]
        let y = cborKeyMap[CoseKeys.y] as! [UInt8]
        
        if x.count != 32 || y.count != 32 {
            throw PasskeysControllerError.invalidPublicKey("Invalid public key length.")
        }
        
        return [0x04] + x + y
    }
}
struct ClientDataJSON: Codable {
    let type: String
    let challenge: String
    let origin: String
    let crossOrigin: Bool?
    let tokenBinding: String?
}


struct PasskeyObject: Codable {
    let id: String
    let publicKey: String
    let counter: UInt32
    let timestamp: Date
    
    init(id: String, publicKey: [UInt8], counter: UInt32) {
        self.id = id
        self.publicKey = publicKey.map { String(format: "%02x", $0) }.joined()
        self.counter = counter
        self.timestamp = Date()
    }
}

func decodeAttestationResult(_ credential: ASAuthorizationPlatformPublicKeyCredentialRegistration) throws -> PasskeyObject? {
    do {
        // Extract data
        let id = credential.credentialID.base64URLEncodedString()
        let clientDataJSON = try JSONDecoder().decode(ClientDataJSON.self, from: credential.rawClientDataJSON)
        

        let attObject: [CtapClientAttKeys: Any] = try decodeCborToMap(bytes: [UInt8](credential.rawAttestationObject!), keyType: CtapClientAttKeys.self)
        
        if attObject[CtapClientAttKeys.authData] == nil {
            throw PasskeysControllerError.missingAuthData
        }
        
        let authData = try AuthData(attObject[CtapClientAttKeys.authData] as! [UInt8])
        let publicKey = try authData.getX962PublicKey()
        
        return PasskeyObject(id: id, publicKey: publicKey, counter: authData.counter)
    } catch {
        throw error
    }
}

extension NSNotification.Name {
    static let UserSignedIn = Notification.Name("UserSignedInNotification")
    static let ModalSignInSheetCanceled = Notification.Name("ModalSignInSheetCanceledNotification")
}

class PasskeysController: NSObject, ASAuthorizationControllerPresentationContextProviding, ASAuthorizationControllerDelegate {
    let domain = "web.daryascam.info"
    var authenticationAnchor: ASPresentationAnchor?
    var isPerformingModalReqest = false

    func signInWith(anchor: ASPresentationAnchor, preferImmediatelyAvailableCredentials: Bool) {
        self.authenticationAnchor = anchor
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)

        // Fetch the challenge from the server. The challenge needs to be unique for each request.
        let challenge = Data()

        let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challenge)

        // Also allow the user to use a saved password, if they have one.
        let passwordCredentialProvider = ASAuthorizationPasswordProvider()
        let passwordRequest = passwordCredentialProvider.createRequest()

        // Pass in any mix of supported sign-in request types.
        let authController = ASAuthorizationController(authorizationRequests: [ assertionRequest, passwordRequest ] )
        authController.delegate = self
        authController.presentationContextProvider = self

        if preferImmediatelyAvailableCredentials {
            // If credentials are available, presents a modal sign-in sheet.
            // If there are no locally saved credentials, no UI appears and
            // the system passes ASAuthorizationError.Code.canceled to call
            // `AccountManager.authorizationController(controller:didCompleteWithError:)`.
            authController.performRequests(options: .preferImmediatelyAvailableCredentials)
        } else {
            // If credentials are available, presents a modal sign-in sheet.
            // If there are no locally saved credentials, the system presents a QR code to allow signing in with a
            // passkey from a nearby device.
            authController.performRequests()
        }

        isPerformingModalReqest = true
    }

    func beginAutoFillAssistedPasskeySignIn(anchor: ASPresentationAnchor) {
        self.authenticationAnchor = anchor

        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)

        // Fetch the challenge from the server. The challenge needs to be unique for each request.
        let challenge = Data()
        let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challenge)

        // AutoFill-assisted requests only support ASAuthorizationPlatformPublicKeyCredentialAssertionRequest.
        let authController = ASAuthorizationController(authorizationRequests: [ assertionRequest ] )
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performAutoFillAssistedRequests()
    }
    
    func signUpWith(userName: String, anchor: ASPresentationAnchor) {
        self.authenticationAnchor = anchor
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)

        // Fetch the challenge from the server. The challenge needs to be unique for each request.
        // The userID is the identifier for the user's account.
        let challenge = Data()
        let userID = Data(UUID().uuidString.utf8)

        let registrationRequest = publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge,
                                                                                                  name: userName, userID: userID)

        // Use only ASAuthorizationPlatformPublicKeyCredentialRegistrationRequests or
        // ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequests here.
        let authController = ASAuthorizationController(authorizationRequests: [ registrationRequest ] )
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performRequests()
        isPerformingModalReqest = true
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let logger = Logger()
        switch authorization.credential {
        case let credentialRegistration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            logger.log("A new passkey was registered: \(credentialRegistration)")
            
            do {
                let decodedAttResp = try decodeAttestationResult(credentialRegistration)
                print(decodedAttResp)
                
            } catch {
                print("Error")
                print(error)
            }
            
            didFinishSignIn()
        case let credentialAssertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            logger.log("A passkey was used to sign in: \(credentialAssertion)")
            // Verify the below signature and clientDataJSON with your service for the given userID.
            // let signature = credentialAssertion.signature
            // let clientDataJSON = credentialAssertion.rawClientDataJSON
            // let userID = credentialAssertion.userID

            // After the server verifies the assertion, sign in the user.
            didFinishSignIn()
        default:
            fatalError("Received unknown authorization type.")
        }

        isPerformingModalReqest = false
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let logger = Logger()
        guard let authorizationError = error as? ASAuthorizationError else {
            isPerformingModalReqest = false
            logger.error("Unexpected authorization error: \(error.localizedDescription)")
            return
        }

        if authorizationError.code == .canceled {
            // Either the system doesn't find any credentials and the request ends silently, or the user cancels the request.
            // This is a good time to show a traditional login form, or ask the user to create an account.
            logger.log("Request canceled.")

            if isPerformingModalReqest {
                didCancelModalSheet()
            }
        } else {
            // Another ASAuthorization error.
            // Note: The userInfo dictionary contains useful information.
            logger.error("Error: \((error as NSError).userInfo)")
        }

        isPerformingModalReqest = false
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return authenticationAnchor!
    }

    func didFinishSignIn() {
        NotificationCenter.default.post(name: .UserSignedIn, object: nil)
    }

    func didCancelModalSheet() {
        NotificationCenter.default.post(name: .ModalSignInSheetCanceled, object: nil)
    }
}

