//
//  Extensions.swift
//  im-hybrid-demo
//
//  Created by Personal on 28/11/2024.
//
import Foundation

extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "") // Remove padding
    }
}

extension UUID {
    func getData() -> Data {
        return withUnsafePointer(to: self.uuid) {
            Data(bytes: $0, count: MemoryLayout.size(ofValue: self.uuid))
        }
    }
}

enum Base64URLError: Error {
    case invalidBase64URL
}

extension String {
    func isValidBase64URL() -> Bool {
        let regex = #"^[A-Za-z0-9-_]*={0,2}$"#
        return self.range(of: regex, options: .regularExpression) != nil
    }
        
    func base64URLDecodedData() throws -> Data {
        guard self.isValidBase64URL() else {
            throw Base64URLError.invalidBase64URL
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
            throw Base64URLError.invalidBase64URL
        }
        
        let data = try self.base64URLDecodedData()
        
        return String(data: data, encoding: .utf8)!
    }
}
