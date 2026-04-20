import SwiftUI

@main
struct SampleApp: App {
    @State private var count = 0

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 20) {
                Text("Count: \(count)")
                    .font(.largeTitle)

                HStack {
                    Button("Decrement") {
                        count -= 1
                    }
                    .keyboardShortcut("-")

                    Button("Increment") {
                        count += 1
                    }
                    .keyboardShortcut("+")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(minWidth: 300, minHeight: 200)
        }
    }
}

// MARK: - Helper Functions

func fibonacci(_ n: Int) -> Int {
    guard n > 1 else { return n }
    return fibonacci(n - 1) + fibonacci(n - 2)
}

enum AppError: Error, LocalizedError {
    case invalidInput(String)
    case networkFailure(code: Int)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let msg):
            return "Invalid input: \(msg)"
        case .networkFailure(let code):
            return "Network failure with code \(code)"
        }
    }
}
