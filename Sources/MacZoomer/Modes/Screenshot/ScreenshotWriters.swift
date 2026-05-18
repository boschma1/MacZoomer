import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// Writes a `CGImage` to the system clipboard as PNG so it pastes cleanly
/// into Mail, Slack, Photoshop, etc.
enum ClipboardWriter {
    static func write(cgImage: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: cgImage)
        if let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        // Also write an NSImage variant so apps that ignore PNG-on-pasteboard
        // (e.g. older AppleScript droplets) still get something usable.
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        pb.writeObjects([image])
    }
}

/// Writes a `CGImage` to a PNG file in the given folder, using a timestamped
/// filename matching macOS's native screenshot convention.
enum ImageFileWriter {
    enum WriteError: LocalizedError {
        case folderUnavailable(URL)
        case destinationCreateFailed
        case finalizeFailed

        var errorDescription: String? {
            switch self {
            case .folderUnavailable(let url):
                return "Folder not available: \(url.path)"
            case .destinationCreateFailed:
                return "Could not create PNG destination."
            case .finalizeFailed:
                return "Could not finalize PNG file."
            }
        }
    }

    static func writePNG(image: CGImage, folder: URL) throws -> URL {
        try ensureFolderExists(folder)
        let url = uniqueFileURL(in: folder)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw WriteError.destinationCreateFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw WriteError.finalizeFailed
        }
        return url
    }

    private static func ensureFolderExists(_ url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: url.path, isDirectory: &isDir) || !isDir.boolValue {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func uniqueFileURL(in folder: URL, baseName: String? = nil, ext: String = "png") -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())
        let core = baseName ?? "MacZoomer Screenshot \(stamp)"

        var candidate = folder.appendingPathComponent("\(core).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(core) (\(suffix)).\(ext)")
            suffix += 1
        }
        return candidate
    }
}
