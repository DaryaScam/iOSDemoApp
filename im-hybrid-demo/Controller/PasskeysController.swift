//
//  PasskeysController.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//


import AuthenticationServices
import Foundation
import os
import SwiftCBOR

// Truthfully stolen from https://docs-assets.developer.apple.com/published/0dc46a3bfa/ConnectingToAServiceWithPasskeys.zip
// https://web.daryascam.info/.well-known/apple-app-site-association

struct PasskeyObject: Codable {
    let id: String
    let publicKey: String
    let counter: UInt32
    let timestamp: Date
    let aaguid: UUID
    var prfSupported: Bool
    var prfFirst: Data?
    var prfSecond: Data?
    
    init(id: String, publicKey: [UInt8], counter: UInt32, aaguid: UUID) {
        self.id = id
        self.publicKey = Data(publicKey).base64Url
        self.counter = counter
        self.timestamp = Date()
        self.aaguid = aaguid
        self.prfFirst = nil
        self.prfSecond = nil
        self.prfSupported = false
    }
    
    mutating func setSalts(first: Data?, second: Data?) {
        self.prfSupported = true
        self.prfFirst = first
        self.prfSecond = second
    }
}

func decodeAttestationResult(_ credential: ASAuthorizationPlatformPublicKeyCredentialRegistration) throws -> PasskeyObject? {
    do {
        // Extract data
        let id = credential.credentialID.base64Url
        // Check origin, challenge, and rpid
        let clientDataJSON = try JSONDecoder().decode(ClientDataJSON.self, from: credential.rawClientDataJSON)

        let attObject: [CtapClientAttKeys: Any] = try decodeCborToMap(bytes: [UInt8](credential.rawAttestationObject!), keyType: CtapClientAttKeys.self)
        
        if attObject[CtapClientAttKeys.authData] == nil {
            throw PasskeyError.missingAuthData
        }
        
        let authData = try AuthData(attObject[CtapClientAttKeys.authData] as! [UInt8])
        let publicKey = try authData.getX962PublicKey()
        
        return PasskeyObject(id: id, publicKey: publicKey, counter: authData.counter, aaguid: authData.aaguid!)
    } catch {
        throw error
    }
}

class PasskeysController: NSObject, ASAuthorizationControllerPresentationContextProviding, ASAuthorizationControllerDelegate {
    var authenticationAnchor: ASPresentationAnchor?
    
    var createPasskeyResult: ((Result<PasskeyObject, Error>) -> Void)?
    
    // TODO
    func signInWith(anchor: ASPresentationAnchor, preferImmediatelyAvailableCredentials: Bool) {
        self.authenticationAnchor = anchor
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: ApplicationConfig.rpId)

        // Fetch the challenge from the server. The challenge needs to be unique for each request.
        let challenge = Data()

        let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challenge)

        // Pass in any mix of supported sign-in request types.
        let authController = ASAuthorizationController(authorizationRequests: [ assertionRequest ] )
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
    }

    // TODO
    func beginAutoFillAssistedPasskeySignIn(anchor: ASPresentationAnchor) {
        self.authenticationAnchor = anchor

        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: ApplicationConfig.rpId)

        // Fetch the challenge from the server. The challenge needs to be unique for each request.
        let challenge = Data()
        let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challenge)

        // AutoFill-assisted requests only support ASAuthorizationPlatformPublicKeyCredentialAssertionRequest.
        let authController = ASAuthorizationController(authorizationRequests: [ assertionRequest ] )
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performAutoFillAssistedRequests()
    }
    
    func createPasskey(userName: String, challenge: Data, userID: Data, prfSalt: Data?, anchor: ASPresentationAnchor, completion: @escaping (Result<PasskeyObject, Error>) -> Void) {
        self.createPasskeyResult = completion
        self.authenticationAnchor = anchor
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: ApplicationConfig.rpId)


        let registrationRequest = publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userID)
        
        
        if #available(iOS 18.0, *) {
            if prfSalt != nil {
                let prfInput = ASAuthorizationPublicKeyCredentialPRFRegistrationInput.self.InputValues(saltInput1: prfSalt!)
                registrationRequest.prf = ASAuthorizationPublicKeyCredentialPRFRegistrationInput.inputValues(prfInput)

                print("entra prf")
            }
    
          

        }
        
        // Use only ASAuthorizationPlatformPublicKeyCredentialRegistrationRequests or
        // ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequests here.
        let authController = ASAuthorizationController(authorizationRequests: [ registrationRequest ] )
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performRequests()
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let logger = Logger()
        switch authorization.credential {
        case let credentialRegistration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            if #available(iOS 18.0, *) {
                
                let prf = credentialRegistration.prf
                print("PRF isSupported: \(prf?.isSupported)")
                print("PRF salt1: \(prf?.first)")
                print("PRF salt2: \(prf?.second)")
            }
            
            print("A new passkey was registered: \(credentialRegistration)")

            do {
                let decodedAttResp = try decodeAttestationResult(credentialRegistration)
                if let decodedAttResp = decodedAttResp {
                    createPasskeyResult?(.success(decodedAttResp))
                } else {
                    getErrorCallback()(PasskeyError.missingAuthData)
                }
            } catch {
                print("Error")
                print(error)
                getErrorCallback()(error)
            }
            
//        case let credentialAssertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
//            logger.log("A passkey was used to sign in: \(credentialAssertion)")
//            // Verify the below signature and clientDataJSON with your service for the given userID.
//            // let signature = credentialAssertion.signature
//            // let clientDataJSON = credentialAssertion.rawClientDataJSON
//            // let userID = credentialAssertion.userID
//
//            // After the server verifies the assertion, sign in the user.
//            didFinishSignIn()
        default:
            if createPasskeyResult != nil {
                getErrorCallback()(PasskeyError.missingAuthData)
            } else {
                fatalError("Received unknown authorization type.")
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let authorizationError = error as? ASAuthorizationError else {
            getErrorCallback()(error)
            return
        }

        if authorizationError.code == .canceled {
            getErrorCallback()(PasskeyError.requestCancelled)
        } else {
            getErrorCallback()(PasskeyError.unexpectedError(error.localizedDescription))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return authenticationAnchor!
    }
    
    func getErrorCallback() -> (Error) -> Void {
        if self.createPasskeyResult != nil {
            
            return { error in self.createPasskeyResult!(.failure(error)) }
        } else {
            fatalError("No error callback provided.")
        }
    }
}

