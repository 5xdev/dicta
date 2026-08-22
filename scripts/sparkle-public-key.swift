// Prints the base64 ed25519 public key for a Sparkle private key file (as exported by
// `generate_keys -x`, i.e. base64 of the 32-byte seed; 64 bytes = legacy seed + public key).
//
//   swift scripts/sparkle-public-key.swift path/to/private.key
//
// CI compares the result with the app's SUPublicEDKey, so a release is never signed with a key
// the installed copies do not trust.
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: sparkle-public-key.swift <private-key-file>\n", stderr)
    exit(2)
}

let raw = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let key = Data(base64Encoded: raw) else {
    fputs("private key is not base64\n", stderr)
    exit(1)
}

switch key.count {
case 32:
    let publicKey = try Curve25519.Signing.PrivateKey(rawRepresentation: key).publicKey
    print(publicKey.rawRepresentation.base64EncodedString())
case 64:
    print(key.suffix(32).base64EncodedString())
default:
    fputs("private key decodes to \(key.count) bytes, expected 32 or 64\n", stderr)
    exit(1)
}
