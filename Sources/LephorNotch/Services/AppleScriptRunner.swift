import AppKit

enum AppleScriptError: Error {
    case notPermitted
    case appNotRunning
    case failed(String)
}

/// NSAppleScript is not thread safe and compiling a script is the expensive part, so each
/// runner keeps one compiled script and serialises access on its own queue.
final class AppleScriptRunner {
    private let queue = DispatchQueue(label: "com.lephor.notch.applescript")
    private var cache: [String: NSAppleScript] = [:]

    func run(_ source: String) -> Result<NSAppleScriptDescriptorBox, AppleScriptError> {
        queue.sync {
            let script: NSAppleScript
            if let cached = cache[source] {
                script = cached
            } else {
                guard let compiled = NSAppleScript(source: source) else {
                    return .failure(.failed("could not compile"))
                }
                cache[source] = compiled
                script = compiled
            }

            var error: NSDictionary?
            let descriptor = script.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                // -1743 = not authorised to send Apple events, -600 = app isn't running.
                if code == -1743 { return .failure(.notPermitted) }
                if code == -600 || code == -609 { return .failure(.appNotRunning) }
                let message = error[NSAppleScript.errorMessage] as? String ?? "unknown"
                return .failure(.failed(message))
            }
            return .success(NSAppleScriptDescriptorBox(descriptor))
        }
    }

    @discardableResult
    func fire(_ source: String) -> Bool {
        if case .success = run(source) { return true }
        return false
    }
}

/// NSAppleEventDescriptor is not Sendable; boxing keeps the compiler honest about the hop.
struct NSAppleScriptDescriptorBox: @unchecked Sendable {
    let descriptor: NSAppleEventDescriptor
    init(_ descriptor: NSAppleEventDescriptor) { self.descriptor = descriptor }
    var string: String { descriptor.stringValue ?? "" }
    var data: Data? { descriptor.data.isEmpty ? nil : descriptor.data }
}
