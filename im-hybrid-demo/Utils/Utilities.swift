//
//  Utilities.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

import Foundation
import SwiftCBOR

enum DecodingError: Error {
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
        throw DecodingError.invalidData("Decoded data is not a CBOR map.")
    }
    
    if Key.RawValue.self == UInt.self {
        throw DecodingError.invalidData("Uint enums are not supported")
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
                throw DecodingError.invalidKeyType("Failed to decode key \(keyString).")
            }
        case let CBOR.negativeInt(keyNegative):
            if let rawKey = cborNegative(Int(keyNegative))  as? Key.RawValue, let castedKey = Key(rawValue: rawKey) {
                keyId = castedKey
            } else {
                throw DecodingError.invalidKeyType("Failed to decode key \(keyNegative).")
            }
        case let CBOR.unsignedInt(keyNumber):
            if let rawKey = Int(keyNumber) as? Key.RawValue, let castedKey = Key(rawValue: rawKey) {
                keyId = castedKey
            } else {
                throw DecodingError.invalidKeyType("Failed to decode key \(keyNumber).")
            }
        default:
            throw DecodingError.invalidKeyType("Key \(key) is not a valid key type.")
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


final class ConsentManager: ObservableObject {
    @Published var userConsented: Bool? = nil

    func waitForUserConsent() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            var completed = false
            let cancellable = $userConsented
                .dropFirst() // Skip the initial value
                .compactMap { $0 } // Ignore nil values
                .first()
                .sink { consent in
                    continuation.resume(returning: consent)
                    completed = true
                }

            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // Timeout after 30 seconds
                
                if !completed {
                    continuation.resume(throwing: NSError(domain: "Timeout", code: -1))
                    cancellable.cancel()
                }
            }
        }
    }
}

func waitTime(_ milliseconds: Int, completion: @escaping (Result<Void, Never>) -> Void) {
    guard milliseconds > 0 else {
        completion(.success(())) // Return immediately for non-positive time
        return
    }

    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
        completion(.success(())) // Call completion after the delay
    }
}
