import AppKit

let arguments = CommandLine.arguments

if let snapshotFlag = arguments.firstIndex(of: "--snapshot") {
    guard snapshotFlag + 1 < arguments.count else {
        FileHandle.standardError.write(Data("usage: SeeImage --snapshot <output.png>\n".utf8))
        exit(2)
    }
    SnapshotRenderer.run(outputPath: arguments[snapshotFlag + 1])
    exit(0)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
