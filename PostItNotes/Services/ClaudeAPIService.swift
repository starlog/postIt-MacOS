import Foundation

class ClaudeAPIService {

    func sendMessage(prompt: String, noteContent: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Users/felix/.local/bin/claude")
            process.arguments = ["-p", "\(prompt)\n\n---\n[Note Content]\n\(noteContent)"]

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus != 0 {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    completion(.failure(ClaudeError.processError(errorOutput)))
                } else if output.isEmpty {
                    completion(.failure(ClaudeError.emptyResponse))
                } else {
                    completion(.success(output))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}

enum ClaudeError: LocalizedError {
    case processError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .processError(let message):
            return "Claude CLI error: \(message)"
        case .emptyResponse:
            return "No response from Claude CLI."
        }
    }
}
