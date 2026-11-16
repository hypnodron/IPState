import CryptoKit
import Foundation

do {
    guard CommandLine.arguments.count == 4 else {
        throw NSError(domain: "IPStateUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Usage: verify-update.swift archive signature-file public-key"])
    }
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
    let attributes = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
    guard let publicKey = Data(base64Encoded: CommandLine.arguments[3]),
          let signatureText = attributes.components(separatedBy: "sparkle:edSignature=\"").dropFirst().first?.components(separatedBy: "\"").first,
          let signature = Data(base64Encoded: signatureText),
          try Curve25519.Signing.PublicKey(rawRepresentation: publicKey).isValidSignature(signature, for: archive) else {
        throw NSError(domain: "IPStateUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey:
            "The archive signature does not match the app's public update key."])
    }
    print("Verified the update archive against the app's public key.")
} catch {
    FileHandle.standardError.write(Data("Update verification failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
