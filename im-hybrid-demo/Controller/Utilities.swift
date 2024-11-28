//
//  Utilities.swift
//  im-hybrid-demo
//

import Foundation
import Security
import CommonCrypto
import SwiftCBOR

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


let blockSize = kCCBlockSizeAES128 // AES block size is always 128 bits (16 bytes)

/// Encrypts a single block of data using AES-256 in ECB mode.
/// - Parameters:
///   - data: 16-byte plaintext block (must match block size).
///   - key: 32-byte AES key (256 bits).
/// - Returns: Encrypted 16-byte block.
func encryptBlock(data: Data, key: Data) throws -> Data {
    guard data.count == blockSize else {
        throw NSError(domain: "Invalid block size", code: -1, userInfo: nil)
    }
    guard key.count == kCCKeySizeAES256 else {
        throw NSError(domain: "Invalid key size", code: -1, userInfo: nil)
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
        throw NSError(domain: "Encryption failed", code: Int(status), userInfo: nil)
    }

    // Convert the result back to Data
    return Data(outputBuffer.prefix(bytesEncrypted))
}


enum DecodingError: Error {
    case invalidData(String)
    case invalidKeyType
}

func cborNegative(_ value: Int) -> Int {
    return -1 - value
}

func decodeCborToMap<Key: RawRepresentable>(
    bytes: [UInt8],
    keyType: Key.Type
) throws -> [Key: Any] where Key.RawValue: Hashable {
    // Decode the CBOR bytes
    guard let decodedCbor = try? CBOR.decode(bytes),
          case let CBOR.map(map) = decodedCbor else {
        throw DecodingError.invalidData("Decoded data is not a CBOR map.")
    }
    
    var resultMap: [Key: Any] = [:]
    
    // Iterate over the CBOR map
    for (key, value) in map {
        var keyId: Key?

//        print(key)

        // Try decoding the key as different CBOR types
        switch key {
        case let CBOR.utf8String(keyString):
            if let rawKey = keyString as? Key.RawValue, let castedKey = Key(rawValue: rawKey) {
                keyId = castedKey
            }
        case let CBOR.negativeInt(keyNegative):
            if let rawKey = cborNegative(Int(keyNegative))  as? Key.RawValue, let castedKey = Key(rawValue: rawKey) {
                keyId = castedKey
            }
        case let CBOR.unsignedInt(keyNumber):
            if let rawKey = Int(keyNumber) as? Key.RawValue, let castedKey = Key(rawValue: rawKey) {
                keyId = castedKey
            }
        default:
            print("Key \(key) has an unknown type. Skipping.")
            throw DecodingError.invalidKeyType
        }
        
        
        // If a matching key is found, handle the value
        if let keyId = keyId {
            switch value {
            case let CBOR.byteString(bytes):
                resultMap[keyId] = bytes
            case let CBOR.boolean(bool):
                resultMap[keyId] = bool
            case let CBOR.unsignedInt(intValue):
                resultMap[keyId] = intValue
            case let CBOR.negativeInt(nintValue):
                let decodedNegative = cborNegative(Int(nintValue))
                resultMap[keyId] = decodedNegative
            case let CBOR.utf8String(string):
                resultMap[keyId] = string
            case let CBOR.map(innerMap):
                resultMap[keyId] = innerMap
            default:
                print("Value for key \(keyId) has an unknown type. Skipping.")
            }
        }
    }
    
    return resultMap
}


func hexToBytes(_ hex: String) throws -> [UInt8] {
    var hexString = hex
    
    // Remove "0x" prefix if present
    if hexString.hasPrefix("0x") {
        hexString = String(hexString.dropFirst(2))
    }
    
    // Ensure the hex string has an even number of characters
    guard hexString.count % 2 == 0 else {
        throw DecodingError.invalidData("Hex string must have an even number of characters.")
    }
    
    // Convert hex string to byte array
    var bytes: [UInt8] = []
    var index = hexString.startIndex
    while index < hexString.endIndex {
        let nextIndex = hexString.index(index, offsetBy: 2)
        let byteString = hexString[index..<nextIndex]
        guard let byte = UInt8(byteString, radix: 16) else {
            throw DecodingError.invalidData("Invalid hex character sequence: \(byteString)")
        }
        bytes.append(byte)
        index = nextIndex
    }
    
    return bytes
}

func uint8ArrayToUUIDT(_ bytes: [UInt8]) throws -> uuid_t {
    // Ensure the array has exactly 16 elements
    guard bytes.count == 16 else {
        throw DecodingError.invalidData("UUID byte array must have exactly 16 elements.")
    }

    // Map the array to a uuid_t tuple
    let uuidTuple: uuid_t = (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    )

    return uuidTuple
}

func localizedDateTimeString(from date: Date, dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .medium) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = dateStyle
    dateFormatter.timeStyle = timeStyle
    dateFormatter.locale = Locale.current // Use the current locale
    return dateFormatter.string(from: date)
}
