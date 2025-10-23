// In AppColors.swift

import SwiftUI

// A centralized struct to hold all the colors for our application's theme.
// This makes it easy to change the entire app's look from one place.
struct AppColors {
    static let background = Color("BackgroundColor")
    static let userBubble = Color("UserBubbleColor")
    static let assistantBubble = Color("AssistantBubbleColor")
    static let primaryText = Color.white
    static let secondaryText = Color.gray.opacity(0.8)
}
