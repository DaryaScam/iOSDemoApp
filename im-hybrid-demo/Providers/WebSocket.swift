//
//  WebSocket.swift
//  im-hybrid-demo
//
//  Created by Personal on 28/11/2024.
//

import Foundation

enum WebSocketError: Error {
    case invalidURL
    case invalidData
    case errorSendingData(Error)
    case wsError(wscode: Int, reason: String)
    case timeout
    case invalidResponse
    case unexpectedMessageType
    case invalidMessageFormat
    case unknownMessageType
}

enum WSMessageType: String, Codable {
    case helloClient = "hello-client"
    case helloMessenger = "hello-messenger"
    case channelReady = "channel-ready"
    
    case message = "message"

    case ack = "ack"
    case error = "error"
}

struct WSMessage: Codable {
    let type: WSMessageType
    let data: String?
    
    static func fromData(_ data: Data) throws -> WSMessage {
        return try JSONDecoder().decode(WSMessage.self, from: data)
    }
    
    func toData() throws -> Data {
        return try JSONEncoder().encode(self)
    }
}

class WebSocketProvider {
    private var ws: URLSessionWebSocketTask?
    private var channelStatus: WSMessageType? = nil

    init(url: String) async throws {
        guard let wsUrl = URL(string: url) else {
            throw WebSocketError.invalidURL
        }

        self.ws = URLSession.shared.webSocketTask(with: wsUrl)
        self.ws?.resume() // Start the WebSocket connection

        // Send initial helloClient message
        let helloMessage = WSMessage(type: .helloMessenger, data: nil)
        try await self.send(message: helloMessage)

        // Await acknowledgment from WebSocket
        let ackMessage = try await self.awaitForMessage(timeout: 5, messageType: .ack)
        print("WebSocket connection established: \(ackMessage)")
        
        let readyMessage = try await self.awaitForMessage(timeout: 5, messageType: .channelReady)
        print("WebSocket connection ready: \(readyMessage)")
        
        self.channelStatus = .channelReady
    }

    func send(message: WSMessage) async throws {
        print("Sending message: \(message)")
        let data = try message.toData()
        try await send(data: data)
    }

    func send(data: Data) async throws {
        print("Sending data: \(String(data: data, encoding: .utf8) ?? "nil")")
        return try await withCheckedThrowingContinuation { continuation in
            self.ws?.send(.data(data)) { error in
                if let error = error {
                    continuation.resume(throwing: WebSocketError.errorSendingData(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func awaitForMessage(
        timeout: TimeInterval = 5,
        messageType: WSMessageType
    ) async throws -> WSMessage {
        return try await withCheckedThrowingContinuation { continuation in
            // Track whether the continuation has been resumed
            var isContinuationResumed = false

            // Create a DispatchWorkItem for timeout handling
            let timeoutWorkItem = DispatchWorkItem {
                if !isContinuationResumed {
                    isContinuationResumed = true
                    continuation.resume(throwing: WebSocketError.timeout)
                }
            }

            // Schedule the timeout work item
            DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            // Receive WebSocket message
            self.ws?.receive { result in
                if isContinuationResumed {
                    return // Prevent double resume
                }

                timeoutWorkItem.cancel() // Cancel timeout

                switch result {
                case .failure(let error):
                    isContinuationResumed = true
                    continuation.resume(throwing: error)

                case .success(let message):
                    do {
                        let wsMessage: WSMessage
                        switch message {
                        case .data(let data):
                            wsMessage = try WSMessage.fromData(data)
                        case .string(let text):
                            guard let data = text.data(using: .utf8) else {
                                throw WebSocketError.invalidMessageFormat
                            }
                            wsMessage = try WSMessage.fromData(data)
                        @unknown default:
                            throw WebSocketError.unknownMessageType
                        }

                        // Check message type
                        if wsMessage.type == messageType {
                            isContinuationResumed = true
                            continuation.resume(returning: wsMessage)
                        } else {
                            throw WebSocketError.unexpectedMessageType
                        }
                    } catch {
                        isContinuationResumed = true
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func listen(onReceive: @escaping (Result<WSMessage, Error>) -> Void) {
        self.ws?.receive { result in
            switch result {
            case .failure(let error):
                onReceive(.failure(error))

            case .success(let message):
                do {
                    let wsMessage: WSMessage
                    switch message {
                    case .data(let data):
                        wsMessage = try WSMessage.fromData(data)

                    case .string(let text):
                        guard let data = text.data(using: .utf8) else {
                            throw WebSocketError.invalidMessageFormat
                        }
                        wsMessage = try WSMessage.fromData(data)

                    @unknown default:
                        throw WebSocketError.unknownMessageType
                    }
                    onReceive(.success(wsMessage))

                    // Continue listening for messages
                    self.listen(onReceive: onReceive)
                } catch {
                    onReceive(.failure(error))
                }
            }
        }
    }
}
