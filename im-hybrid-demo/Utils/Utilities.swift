//
//  Utilities.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

import Foundation

enum DecodingError: Error {
    case invalidData(String)
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
