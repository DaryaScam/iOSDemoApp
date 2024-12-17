//
//  CBOR.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

import SwiftCBOR

enum CborError: Error {
    case invalidData(String)
    case invalidKeyType(String)
}

func cborNegative(_ value: Int) -> Int {
    return -1 - value
}

func decodeCborToMap<Key: RawRepresentable>(
    bytes: [UInt8],
    keyType: Key.Type
) throws -> [Key: Any] where Key.RawValue: Hashable {
    // Decode the CBOR bytes
    
    let tryDecodedCbor = try? CBOR.decode(bytes)
    guard let decodedCbor = try? CBOR.decode(bytes),
          case let CBOR.map(map) = decodedCbor else {
        throw CborError.invalidData("Decoded data is not a CBOR map.")
    }
    
    if Key.RawValue.self == UInt.self {
        throw CborError.invalidData("Uint enums are not supported")
    }

    var resultMap: [Key: Any] = [:]
    
    // Iterate over the CBOR map
    for (key, value) in map {
        var keyId: Key?
        
        // Try decoding the key as different CBOR types
        switch key {
        case let CBOR.utf8String(keyString):
            if let rawKey = keyString as? Key.RawValue, let castedKey = Key(rawValue: rawKey) {
                keyId = castedKey
            } else {
                throw CborError.invalidKeyType("Failed to decode key \(keyString).")
            }
        case let CBOR.negativeInt(keyNegative):
            if let rawKey = cborNegative(Int(keyNegative))  as? Key.RawValue, let castedKey = Key(rawValue: rawKey) {
                keyId = castedKey
            } else {
                throw CborError.invalidKeyType("Failed to decode key \(keyNegative).")
            }
        case let CBOR.unsignedInt(keyNumber):
            if let rawKey = Int(keyNumber) as? Key.RawValue, let castedKey = Key(rawValue: rawKey) {
                keyId = castedKey
            } else {
                throw CborError.invalidKeyType("Failed to decode key \(keyNumber).")
            }
        default:
            throw CborError.invalidKeyType("Key \(key) is not a valid key type.")
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
