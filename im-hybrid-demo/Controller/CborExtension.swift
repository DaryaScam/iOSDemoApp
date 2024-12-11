//
//  CborExtension.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

import SwiftCBOR

extension CBOR {
    func asUInt64() -> UInt64? {
        if case let CBOR.unsignedInt(value) = self {
            return value
        }
        return nil
    }
    
    func asByteString() -> [UInt8]? {
        if case let CBOR.byteString(value) = self {
            return value
        }
        return nil
    }
    
    func asString() -> String? {
        if case let CBOR.utf8String(value) = self {
            return value
        }
        return nil
    }
    
    func asBool() -> Bool? {
        if case let CBOR.boolean(value) = self {
            return value
        }
        return nil
    }
}
