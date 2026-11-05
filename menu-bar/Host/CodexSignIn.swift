import Foundation

enum CodexSignIn {
    enum SignInError: LocalizedError {
        case missingCLI, incomplete, wrongAccount, invalidCredential, cancelled

        var errorDescription: String? {
            switch self {
            case .missingCLI: return "Install Codex CLI or the ChatGPT desktop app, then try again."
            case .incomplete: return "Sign-in did not complete. Try again, and close any other Codex login first."
            case .wrongAccount: return "A different account was selected. Try again and choose the email on this card."
            case .invalidCredential: return "Sign-in did not return a valid ChatGPT credential. Please try again."
            case .cancelled: return "Sign-in was cancelled."
            }
        }
    }

    static func directoryName(for accountID: String) -> String {
        Data(accountID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Accept only the selected user, before replacing any stored credential.
    static func installCredential(from source: URL, accountID: String, destination: URL) throws {
        let data = try Data(contentsOf: source)
        guard let auth = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              auth["auth_mode"] as? String == "chatgpt",
              let tokens = auth["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String else {
            throw SignInError.invalidCredential
        }
        let identity = DirectUsageEngine.codexIdentity(token, fallbackAccountId: tokens["account_id"] as? String)
        guard let user = identity.userId ?? identity.email ?? identity.teamId,
              let expiry = identity.expiresAt, expiry > Date().timeIntervalSince1970 else {
            throw SignInError.invalidCredential
        }
        guard "codex:\(user)" == accountID else { throw SignInError.wrongAccount }
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    @MainActor
    final class Session {
        private var process: Process?
        private var timeout: Task<Void, Never>?
        private var cancelled = false

        func start(accountID: String, completion: @escaping (Result<Void, Error>) -> Void) throws {
            let candidates = [
                "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                "/usr/local/bin/codex", "/opt/homebrew/bin/codex"
            ]
            guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw SignInError.missingCLI
            }
            let root = UsageStateStore.supportDirectory
            let pending = root.appendingPathComponent("SignIn/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let destination = root.appendingPathComponent("Accounts/\(directoryName(for: accountID))/auth.json")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["-c", "cli_auth_credentials_store=\"file\"", "login"]
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = pending.path
            environment.removeValue(forKey: "CODEX_ACCESS_TOKEN")
            environment.removeValue(forKey: "OPENAI_API_KEY")
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    guard let self else { return }
                    defer { try? FileManager.default.removeItem(at: pending.appendingPathComponent("auth.json")) }
                    self.timeout?.cancel()
                    self.process = nil
                    do {
                        if self.cancelled { throw SignInError.cancelled }
                        guard process.terminationStatus == 0 else { throw SignInError.incomplete }
                        try installCredential(from: pending.appendingPathComponent("auth.json"), accountID: accountID, destination: destination)
                        completion(.success(()))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
            self.process = process
            try process.run()
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
                self?.cancel()
            }
        }

        func cancel() {
            cancelled = true
            timeout?.cancel()
            if let process, process.isRunning { process.terminate() }
        }
    }
}
