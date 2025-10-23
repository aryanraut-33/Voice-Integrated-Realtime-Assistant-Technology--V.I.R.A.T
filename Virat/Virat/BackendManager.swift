import Foundation

class BackendManager {
    static let shared = BackendManager()
    private var backendProcess: Process?
    private let baseURL = URL(string: "http://127.0.0.1:5001")!

    func startBackend() {
        // IMPORTANT: This path assumes your Xcode project ('Virat') and your
        // backend script ('virat_backend') are in the same parent folder.
        // Adjust the path if your structure is different.
        let scriptPath = "../virat_backend/app.py"
        let venvPath = "../virat_backend/venv/bin/python3"
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: venvPath)
        task.arguments = [scriptPath]
        
        // Set the working directory for the script
        task.currentDirectoryURL = URL(fileURLWithPath: "../virat_backend/")

        do {
            try task.run()
            self.backendProcess = task
            print("✅ Backend process started successfully.")
        } catch {
            print("❌ Failed to start backend process: \(error)")
        }
    }

    func stopBackend() {
        backendProcess?.terminate()
        print("🛑 Backend process terminated.")
    }

    func sendQuery(text: String) {
        let url = baseURL.appendingPathComponent("/ask")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["query": text]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request).resume()
    }

    func fetchUpdates(completion: @escaping ([Message]) -> Void) {
        let url = baseURL.appendingPathComponent("/get_updates")
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data {
                do {
                    let response = try JSONDecoder().decode(ConversationResponse.self, from: data)
                    DispatchQueue.main.async {
                        completion(response.conversation)
                    }
                } catch {
                    print("JSON Decoding Error: \(error)")
                }
            } else if let error = error {
                print("Fetch Error: \(error)")
            }
        }.resume()
    }
}
