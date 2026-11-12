import AppKit

let arguments = CommandLine.arguments

if let snapshotFlag = arguments.firstIndex(of: "--snapshot") {
    guard snapshotFlag + 1 < arguments.count else {
        FileHandle.standardError.write(Data("usage: SeeImage --snapshot <output.png>\n".utf8))
        exit(2)
    }
    let outputPath = arguments[snapshotFlag + 1]
    let inputs = arguments[(snapshotFlag + 2)...]
        .filter { !$0.hasPrefix("-") }
        .map { raw -> URL in
            if let url = URL(string: raw),
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "file"].contains(scheme) {
                return url
            }
            return URL(fileURLWithPath: raw)
        }
    SnapshotRenderer.run(outputPath: outputPath, inputs: inputs)
    exit(0)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
