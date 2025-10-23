// In Models.swift

import Foundation

// This struct MUST match the JSON keys sent by the Python backend's /get_updates endpoint.
struct Message: Codable, Identifiable {
    let id = UUID()
    let role: String
    let text: String // The key here must be "text"

    // We only need CodingKeys if the Swift property names are different from the JSON keys.
    // Since they match, this is optional but good practice.
    enum CodingKeys: String, CodingKey {
        case role, text
    }
}

struct ConversationResponse: Codable {
    let conversation: [Message]
}
