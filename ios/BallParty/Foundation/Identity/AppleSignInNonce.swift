import CryptoKit
import Foundation

/// A raw/hashed nonce pair for Sign in with Apple's replay-protection dance:
/// the hash goes on the `ASAuthorizationAppleIDRequest`, the raw value goes to
/// Supabase's `signInWithIdToken` so it can check the id token's `nonce` claim
/// against it.
enum AppleSignInNonce {
    static func generate(length: Int = 32) -> (raw: String, hashed: String) {
        let raw = randomString(length: length)
        return (raw, sha256(raw))
    }

    static func randomString(length: Int) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            precondition(status == errSecSuccess, "Unable to generate secure random bytes: \(status)")

            for byte in randomBytes where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }

        return result
    }

    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
