// Points macOS's image file associations at Sketchy.
// Usage: swift tools/SetDefaultApp.swift [/path/to/Sketchy.app]
import AppKit
import UniformTypeIdentifiers

let appPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/Applications/Sketchy.app"
let appURL = URL(fileURLWithPath: appPath)
guard FileManager.default.fileExists(atPath: appPath) else {
    print("No app bundle at \(appPath)")
    exit(1)
}

let typeIDs = [
    "public.png", "public.jpeg", "public.tiff", "com.compuserve.gif",
    "com.microsoft.bmp", "public.heic", "public.heif", "org.webmproject.webp",
    "gg.lode.sketchy.document"
]

let group = DispatchGroup()
var failures: [String] = []

for id in typeIDs {
    guard let type = UTType(id) else { continue }
    group.enter()
    NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
        if let error { failures.append("\(id): \(error.localizedDescription)") }
        group.leave()
    }
}
group.wait()

for id in typeIDs {
    guard let type = UTType(id) else { continue }
    let current = NSWorkspace.shared.urlForApplication(toOpen: type)?.lastPathComponent ?? "none"
    print(id.padding(toLength: 32, withPad: " ", startingAt: 0), "->", current)
}
if !failures.isEmpty {
    print("\nFailed:")
    failures.forEach { print("  " + $0) }
    exit(1)
}
