//
//  Extensions.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

import Foundation

extension UInt32 {
    var dataLE: Data {
        var int = self.littleEndian
        return Data(bytes: &int, count: MemoryLayout.size(ofValue: int))
    }
    
    var dataBE: Data {
        var int = self.bigEndian
        return Data(bytes: &int, count: MemoryLayout.size(ofValue: int))
    }
}

extension Data {
    func encodeToBase64Url() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "") // Remove padding
    }
    
    func encodeToHex() -> String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}

extension UUID {
    func getData() -> Data {
        return withUnsafePointer(to: self.uuid) {
            Data(bytes: $0, count: MemoryLayout.size(ofValue: self.uuid))
        }
    }
}

enum StringDecoderError: Error {
    case invalidBase64URL
    case invalidHex
}

extension String {
    func isValidBase64URL() -> Bool {
        let regex = #"^[A-Za-z0-9-_]*={0,2}$"#
        return self.range(of: regex, options: .regularExpression) != nil
    }
    
    func isValidHex() -> Bool {
        let regex = #"^0x[0-9a-fA-F]*$"#
        return self.range(of: regex, options: .regularExpression) != nil
    }
        
    func base64URLDecodedData() throws -> Data {
        guard self.isValidBase64URL() else {
            throw StringDecoderError.invalidBase64URL
        }
        
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding
        let padding = base64.count % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: 4 - padding))
        }
        
        return Data(base64Encoded: base64)!
    }
    
    func base64URLDecodedString() throws -> String {
        guard self.isValidBase64URL() else {
            throw StringDecoderError.invalidBase64URL
        }
        
        let data = try self.base64URLDecodedData()
        
        return String(data: data, encoding: .utf8)!
    }
    
    
    func decodeHex() throws -> [UInt8] {
        guard self.isValidHex() else {
            throw StringDecoderError.invalidHex
        }
    
        var hexString = self
        
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
    
    func hexDecodedData() throws -> Data {
        let bytes = try self.decodeHex()
        return Data(bytes)
    }
}
