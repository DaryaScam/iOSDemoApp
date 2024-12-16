//
//  WebSocket.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

@preconcurrency import Foundation

enum WebSocketError: Error {
    case invalidURL
    case invalidData(String)
    case errorSendingData(Error)
    case wsError(wscode: Int, reason: String)
    case timeout
    case invalidResponse
    case alreadyInitialized
    
    case unexpectedMessageType
    case invalidMessageFormat
    case unknownMessageType
}

enum WSMessageType: String, Codable {
    case helloClient = "hello-client"
    case helloMessenger = "hello-messenger"
    case channelReady = "channel-ready" // WebSocketOnly
    case hybridTunnelReady = "hybrid-tunnel-ready"
    
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
        
        self.channelStatus = .hybridTunnelReady
            
        print("WebSocket connection raw tunnel ready")
    }
    
    func initWebSessionChannel() async throws {
        if self.channelStatus == .channelReady {
            throw WebSocketError.alreadyInitialized
        }
        
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
        timeout: TimeInterval = 5000,
        messageType: WSMessageType
    ) async throws -> WSMessage {
        let rawMessage: String = try await awaitForRawMessage()
        let message = try JSONDecoder().decode(WSMessage.self, from: rawMessage.data(using: .utf8)!)
        return message
    }
    
    func awaitForRawMessage<T: Decodable>(
        timeout: TimeInterval = 5000
    ) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            var isContinuationResumed = false

            let timeoutWorkItem = DispatchWorkItem {
                if !isContinuationResumed {
                    isContinuationResumed = true
                    continuation.resume(throwing: WebSocketError.timeout)
                }
            }

            DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            self.ws?.receive { result in
                if isContinuationResumed {
                    return
                }

                timeoutWorkItem.cancel()

                switch result {
                case .failure(let error):
                    isContinuationResumed = true
                    continuation.resume(throwing: error)
                    
                case .success(let message):
                    if case .data(let data) = message {
                        if T.self == Data.self {
                            isContinuationResumed = true
                            continuation.resume(returning: data as! T)
                        } else {
                            continuation.resume(throwing: WebSocketError.invalidData("Expected Data"))
                        }
                    } else if case .string(let text) = message {
                        if T.self == String.self {
                            isContinuationResumed = true
                            continuation.resume(returning: text as! T)
                        } else {
                            continuation.resume(throwing: WebSocketError.invalidData("Expected String"))
                        }
                    } else {
                        continuation.resume(throwing: WebSocketError.unexpectedMessageType)
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
    
    func close() async {
        self.ws?.cancel()
    }
}
