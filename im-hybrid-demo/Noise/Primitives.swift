//
//  Primitives.swift
//  im-hybrid-demo
//
//  Created by Personal on 15/12/2024.
//

import Foundation
import CryptoKit

func HKDF3(ck: Data, ikm: Data) -> HKDF3Output {
    let salt = ck
    let info = Data()
    let keyMaterial = ikm

    let hkdf = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: keyMaterial), salt: salt, info: info, outputByteCount: 32 * 3)
    let hmac = Data(hkdf.withUnsafeBytes { Data($0) })

    return HKDF3Output(
        o1: hmac.subdata(in: 0..<32),
        o2: hmac.subdata(in: 32..<64),
        o3: hmac.subdata(in: 64..<96)
    )
}
