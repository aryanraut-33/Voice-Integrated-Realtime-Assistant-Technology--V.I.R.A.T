// In ViratApp.swift

import SwiftUI

@main
struct ViratApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // --- UI ENHANCEMENTS FOR THE WINDOW ---
        .windowStyle(.hiddenTitleBar) // Hides the top title bar for a seamless look.
        .windowResizability(.contentSize) // Makes the window size adapt to its content.
    }
}
