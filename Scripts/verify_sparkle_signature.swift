import CryptoKit
import Foundation

let encodedPublicKey = try String(
    contentsOfFile: CommandLine.arguments[1],
    encoding: .utf8
).trimmingCharacters(in: .whitespacesAndNewlines)
let encodedSignature = CommandLine.arguments[2]
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))

guard let publicKeyData = Data(base64Encoded: encodedPublicKey) else {
    fatalError("Sparkle public key is not valid base64")
}
guard let signature = Data(base64Encoded: encodedSignature) else {
    fatalError("Sparkle signature is not valid base64")
}

let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
guard publicKey.isValidSignature(signature, for: archive) else {
    fatalError("Sparkle signature does not verify against the committed public key")
}
