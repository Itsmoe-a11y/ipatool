import Foundation
import Combine

@MainActor
public final class AccountViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public var session: AccountSession? = nil
    @Published public var isCheckingAuth: Bool = false
    @Published public var isAuthenticating: Bool = false
    @Published public var authErrorMessage: String? = nil

    // Form Fields
    @Published public var emailInput: String = ""
    @Published public var passwordInput: String = ""
    @Published public var twoFactorCodeInput: String = ""
    @Published public var requires2FA: Bool = false

    // Diagnostics
    @Published public var binaryDiagnostics: [String: String] = [:]
    @Published public var ipatoolVersion: String = "Checking..."
    @Published public var isRunningDiagnostics: Bool = false

    private let processRunner = ProcessRunner.shared
    private let emailCacheKey = "saved_apple_id_email"

    public init() {
        loadSavedEmail()
        refreshDiagnostics()
        Task {
            await checkAuthStatus()
        }
    }

    private func loadSavedEmail() {
        if let saved = UserDefaults.standard.string(forKey: emailCacheKey) {
            self.emailInput = saved
        }
    }

    // MARK: - Check Authentication Status (`auth info`)
    public func checkAuthStatus() async {
        self.isCheckingAuth = true
        self.authErrorMessage = nil

        do {
            let result = try await processRunner.run(args: ["auth", "info", "--format", "json"])
            let output = result.output

            if let parsedSession = parseAccountSession(from: output) {
                self.session = parsedSession
                self.emailInput = parsedSession.email
                UserDefaults.standard.set(parsedSession.email, forKey: emailCacheKey)
            } else if output.lowercased().contains("authenticated") || output.lowercased().contains("email") {
                // Heuristic parse
                let email = extractEmail(from: output) ?? self.emailInput
                self.session = AccountSession(email: email.isEmpty ? "Authenticated User" : email)
            } else {
                self.session = nil
            }
            self.isCheckingAuth = false
        } catch {
            // Not authenticated or error
            self.session = nil
            self.isCheckingAuth = false
        }
    }

    // MARK: - Login with Apple ID
    public func login() async {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordInput

        guard !email.isEmpty else {
            self.authErrorMessage = "Please enter your Apple ID email."
            return
        }

        guard !password.isEmpty else {
            self.authErrorMessage = "Please enter your password."
            return
        }

        self.isAuthenticating = true
        self.authErrorMessage = nil

        var args = [
            "auth", "login",
            "--email", email,
            "--password", password,
            "--format", "json",
            "--non-interactive"
        ]

        if requires2FA && !twoFactorCodeInput.isEmpty {
            args += ["--auth-code", twoFactorCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        do {
            let result = try await processRunner.run(args: args)
            let output = result.output

            // Check if 2FA code is needed
            if output.lowercased().contains("2fa") ||
               output.lowercased().contains("two-factor") ||
               output.lowercased().contains("code") ||
               output.lowercased().contains("auth-code") {
                self.requires2FA = true
                self.authErrorMessage = "Two-Factor Authentication code required. Please enter the code sent to your Apple devices."
                self.isAuthenticating = false
                return
            }

            // Successfully logged in
            self.requires2FA = false
            self.twoFactorCodeInput = ""
            self.passwordInput = ""
            UserDefaults.standard.set(email, forKey: emailCacheKey)

            // Refresh account session
            await checkAuthStatus()
            self.isAuthenticating = false
        } catch {
            let errorText = error.localizedDescription

            if errorText.lowercased().contains("2fa") ||
               errorText.lowercased().contains("two-factor") ||
               errorText.lowercased().contains("auth-code") {
                self.requires2FA = true
                self.authErrorMessage = "Two-Factor Authentication required. Enter the 6-digit code above."
            } else {
                self.authErrorMessage = errorText
            }
            self.isAuthenticating = false
        }
    }

    // MARK: - Logout / Revoke Session (`auth revoke`)
    public func revoke() async {
        self.isAuthenticating = true
        self.authErrorMessage = nil

        do {
            _ = try await processRunner.run(args: ["auth", "revoke"])
            self.session = nil
            self.requires2FA = false
            self.twoFactorCodeInput = ""
            self.isAuthenticating = false
        } catch {
            self.authErrorMessage = "Failed to revoke: \(error.localizedDescription)"
            self.isAuthenticating = false
        }
    }

    // MARK: - System Diagnostics
    public func refreshDiagnostics() {
        self.isRunningDiagnostics = true
        self.binaryDiagnostics = processRunner.diagnosticInfo()

        Task {
            do {
                let result = try await processRunner.run(args: ["--version"])
                let v = ProcessRunner.stripAnsiCodes(result.output).trimmingCharacters(in: .whitespacesAndNewlines)
                self.ipatoolVersion = v.isEmpty ? "ipatool 2.8.1 (iOS arm64)" : v
            } catch {
                self.ipatoolVersion = "Unknown (\(error.localizedDescription))"
            }
            self.isRunningDiagnostics = false
        }
    }

    // MARK: - Parsing Helpers
    private func parseAccountSession(from output: String) -> AccountSession? {
        struct RawAccountInfo: Codable {
            let email: String?
            let name: String?
            let account: RawAccount?
        }
        struct RawAccount: Codable {
            let email: String?
            let name: String?
            let appleID: String?
            let storefront: String?
        }

        guard let data = output.data(using: .utf8) else { return nil }

        if let raw = try? JSONDecoder().decode(RawAccountInfo.self, from: data) {
            let e = raw.email ?? raw.account?.email
            if let email = e, !email.isEmpty {
                return AccountSession(
                    email: email,
                    name: raw.name ?? raw.account?.name,
                    appleID: raw.account?.appleID,
                    storefront: raw.account?.storefront
                )
            }
        }

        // Try extracting via regex
        if let email = extractEmail(from: output) {
            return AccountSession(email: email)
        }

        return nil
    }

    private func extractEmail(from text: String) -> String? {
        let pattern = #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: nsRange),
           let range = Range(match.range, in: text) {
            return String(text[range])
        }
        return nil
    }
}
