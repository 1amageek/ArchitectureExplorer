import Foundation

struct CapturedInputs: Sendable {
  let files: [String: Data]
  let totalBytes: Int
}
