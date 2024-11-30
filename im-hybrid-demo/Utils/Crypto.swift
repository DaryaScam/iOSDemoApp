//
//  Crypto.swift
//  im-hybrid-demo
//
//  Created by Personal on 30/11/2024.
//

import Security
import CommonCrypto
import CryptoKit
import Foundation

enum RandomByteError: Error {
    case generationFailed
}

func generateRandomBytes(_ length: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: length)
    let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
    
    guard status == errSecSuccess else {
        throw RandomByteError.generationFailed
    }
    
    return Data(bytes)
}


// Encryption

enum EncryptionError: Error {
    case invalidKeySize(String)
    case invalidBlockSize
    case encryptionFailed
}

let blockSize = kCCBlockSizeAES128 // AES block size is always 128 bits (16 bytes)

/// Encrypts a single block of data using AES-256 in ECB mode.
/// - Parameters:
///   - data: 16-byte plaintext block (must match block size).
///   - key: 32-byte AES key (256 bits).
/// - Returns: Encrypted 16-byte block.
func encryptBlock(data: Data, key: Data) throws -> Data {
    guard data.count == blockSize else {
        throw EncryptionError.invalidBlockSize
    }
    guard key.count == kCCKeySizeAES256 else {
        throw EncryptionError.invalidKeySize("Expected 32-byte key, got \(key.count) bytes.")
    }

    // Allocate output buffer manually to avoid overlapping access
    var outputBuffer = [UInt8](repeating: 0, count: blockSize)
    var bytesEncrypted = 0

    let status = data.withUnsafeBytes { plaintextBytes in
        key.withUnsafeBytes { keyBytes in
            CCCrypt(
                CCOperation(kCCEncrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionECBMode), // ECB Mode (no IV)
                keyBytes.baseAddress, key.count,
                nil, // No IV required for ECB
                plaintextBytes.baseAddress, data.count,
                &outputBuffer, outputBuffer.count,
                &bytesEncrypted
            )
        }
    }

    guard status == kCCSuccess else {
        throw EncryptionError.encryptionFailed
    }

    // Convert the result back to Data
    return Data(outputBuffer.prefix(bytesEncrypted))
}

func blockEncryptThenMac(data: Data, key: Data) throws -> Data {
    if key.count != 64 {
        throw EncryptionError.invalidKeySize("Expected 64-byte key, got \(key.count) bytes.")
    }
    
    let encryptionKey = key.prefix(32)
    let macKey = key.suffix(32)
    
    var postfixedData = data
    if postfixedData.count % blockSize != 0 {
        postfixedData += Data(repeating: 0, count: blockSize - (postfixedData.count % blockSize))
    }
    
    let encryptedData = try encryptBlock(data: postfixedData, key: encryptionKey)
    
    let mac = HMAC<SHA256>.authenticationCode(for: encryptedData, using: SymmetricKey(data: macKey))
    
    return mac.prefix(16) + encryptedData
}


func generateEcdhKeyPair() -> (publicKey: Data, privateKey: P256.KeyAgreement.PrivateKey) {
    let privateKey = P256.KeyAgreement.PrivateKey()
    let publicKey = Data([0x04]) + privateKey.publicKey.rawRepresentation
    
    return (publicKey, privateKey)
}

func deriveECDHSharedSecret(privateKey: P256.KeyAgreement.PrivateKey, publicKey: Data) throws -> SharedSecret {
    let publicKeyData = try P256.KeyAgreement.PublicKey(x963Representation: publicKey)
    let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKeyData)
    
    return sharedSecret
}


func verifyES256Signature(derSignature: Data, data: Data, publicKey: Data) throws -> Bool {
    let publicKeyData = try P256.Signing.PublicKey(x963Representation: publicKey)
    let signatureData = try P256.Signing.ECDSASignature(derRepresentation: derSignature)
    
    let dataHash = SHA256.hash(data: data)
    
    return publicKeyData.isValidSignature(signatureData, for: dataHash)
}

func getSha256Digest(_ data: Data) -> [UInt8] {
    return [UInt8](SHA256.hash(data: data))
}

func encryptAesGcm(data: Data, key: SymmetricKey) throws -> Data {
    let sealedBox = try AES.GCM.seal(data, using: key)
    return sealedBox.combined!
}

