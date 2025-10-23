// In ContentView.swift

import SwiftUI

struct ContentView: View {
    @State private var conversation: [Message] = []
    @State private var textInput: String = ""
    @State private var lastMessageCount = 0
    
    // Observe the speech synthesizer to show/hide the "Stop" button.
    @ObservedObject private var speechSynthesizer = SpeechSynthesizer.shared
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER ---
            HStack {
                Image(systemName: "sparkle")
                Text("V.I.R.A.T")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                Image(systemName: "sparkle")
            }
            .foregroundColor(AppColors.primaryText)
            .padding()
            .frame(maxWidth: .infinity)
            .background(AppColors.assistantBubble.opacity(0.5))

            // --- CONVERSATION SCROLL VIEW ---
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(conversation) { message in
                            MessageView(message: message)
                        }
                    }
                    .padding()
                }
                .onChange(of: conversation.count) {
                    if let lastMessage = conversation.last {
                        withAnimation(.spring()) {
                            scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // --- INPUT AREA ---
            HStack(spacing: 15) {
                // Show the Stop button only when the assistant is speaking
                if speechSynthesizer.isSpeaking {
                    Button(action: {
                        speechSynthesizer.stopSpeaking()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.red)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Text input field
                TextField("Type your message...", text: $textInput, onCommit: sendMessage)
                    .font(.system(.body, design: .rounded))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(AppColors.assistantBubble)
                    .cornerRadius(20)
                
                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(AppColors.userBubble)
                }
                .disabled(textInput.isEmpty)
            }
            .padding()
            .animation(.easeInOut, value: speechSynthesizer.isSpeaking)
        }
        .background(.regularMaterial) // This creates the frosted glass effect!
        .foregroundColor(AppColors.primaryText)
        .frame(minWidth: 400, idealWidth: 500, minHeight: 300, idealHeight: 600)
        .onAppear(perform: setup)
        .onDisappear(perform: BackendManager.shared.stopBackend)
        .onReceive(timer) { _ in
            fetchUpdates()
        }
    }
    
    private func setup() { BackendManager.shared.startBackend() }
    
    private func sendMessage() {
        guard !textInput.isEmpty else { return }
        BackendManager.shared.sendQuery(text: textInput)
        self.textInput = ""
    }
    
    private func fetchUpdates() {
        BackendManager.shared.fetchUpdates { newConversation in
            self.conversation = newConversation
            
            if conversation.count > lastMessageCount, let lastMessage = conversation.last, lastMessage.role == "model" {
                speechSynthesizer.speak(lastMessage.text)
            }
            
            self.lastMessageCount = conversation.count
        }
    }
}

// --- A DEDICATED VIEW FOR EACH CHAT BUBBLE ---
struct MessageView: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer() // Pushes the bubble to the right
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(.body, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == "user" ? AppColors.userBubble : AppColors.assistantBubble)
                    .cornerRadius(16)
            }
            .shadow(radius: 2, y: 1)
            
            if message.role != "user" {
                Spacer() // Pushes the bubble to the left
            }
        }
    }
}
