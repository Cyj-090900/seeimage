import Foundation

/// One picture in the gallery: either a local file or a remote URL.
struct ImageItem: Equatable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    var isRemote: Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var fileExtension: String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "png" : ext
    }

    /// A reasonable default file name for "存储图片…".
    var suggestedFileName: String {
        let name = url.deletingPathExtension().lastPathComponent
        let base = name.isEmpty ? "图片" : name
        return "\(base).\(fileExtension)"
    }
}
