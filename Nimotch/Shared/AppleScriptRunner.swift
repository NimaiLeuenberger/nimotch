import Foundation

/// Runs AppleScript off the main thread (on one serial queue, NSAppleScript isn't thread-safe).
enum AppleScriptRunner {
    struct Failure: Error, Sendable {
        let code: Int
        let message: String
        /// -1743: the user denied nimotch Automation access to the target app.
        var isNotAuthorized: Bool { code == -1743 }
    }

    private static let queue = DispatchQueue(label: "com.nimai.nimotch.applescript")

    static func run(_ source: String) async -> Result<String, Failure> {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
                    let message = (error[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
                    continuation.resume(returning: .failure(Failure(code: code, message: message)))
                } else {
                    continuation.resume(returning: .success(output?.stringValue ?? ""))
                }
            }
        }
    }
}
