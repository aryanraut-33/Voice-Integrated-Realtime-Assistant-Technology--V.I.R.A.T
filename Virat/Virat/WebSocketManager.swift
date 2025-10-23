// In WebSocketManager.swift

import Foundation

class WebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    
    // @Published properties will automatically update the SwiftUI view.
    @Published var isTranscribing = false
    @Published var liveTranscript = ""
    
    func connect() {
        guard let url = URL(string: "ws://127.0.0.1:5001/socket.io/?EIO=4&transport=websocket") else { return }
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // This is a handshake required by Flask-SocketIO
        send(message: "2probe")
        
        receiveMessages()
    }
    
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("WebSocket receiving error: \(error)")
            case .success(let message):
                if case .string(let text) = message {
                    self?.handleSocketMessage(text)
                }
                // Continue listening for the next message
                self?.receiveMessages()
            }
        }
    }
    
    private func handleSocketMessage(_ text: String) {
        DispatchQueue.main.async {
            // This is part of the Socket.IO protocol handshake
            if text == "3probe" { self.send(message: "5") }
            
            // This is where we handle our custom events from the Python server
            if text.contains("start_transcribing") {
                self.isTranscribing = true
                self.liveTranscript = "Listening..."
            } else if text.contains("partial_transcript") {
                // Parse the JSON-like string from the server
                if let range = text.range(of: "\\{\"text\":.*?\\}\"", options: .regularExpression),
                   let data = String(text[range]).data(using: .utf8) {
                    let jsonString = String(data: data, encoding: .utf8)?
                        .replacingOccurrences(of: "\\", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if let jsonData = jsonString?.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                       let transcript = json["text"] as? String {
                        self.liveTranscript = transcript
                    }
                }
            }
        }
    }
    
    func send(message: String) {
        webSocketTask?.send(.string(message)) { error in
            if let error = error {
                print("WebSocket sending error: \(error)")
            }
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        DispatchQueue.main.async {
            self.isTranscribing = false
            self.liveTranscript = ""
        }
    }
}
