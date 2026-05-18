import Foundation

/// Wraps the system `ffmpeg` binary to convert an MP4 produced by
/// ``RecordingMode`` into an optimised GIF using a two-pass
/// `palettegen` / `paletteuse` pipeline. Output quality matches what
/// ``scripts/mp4-to-gif.sh`` produces — high-fidelity colors at modest
/// file sizes via Sierra-Lite dithering against a global palette.
///
/// `ffmpeg` is **not bundled** with the app. If it's missing the export
/// throws ``GIFExporter/Error/ffmpegNotInstalled`` so the UI layer can
/// surface a friendly `brew install ffmpeg` message.
enum GIFExporter {
    enum Error: LocalizedError {
        case ffmpegNotInstalled
        case sourceMissing(URL)
        case ffmpegFailed(stage: String, exitCode: Int32, stderr: String)
        case paletteMissing

        var errorDescription: String? {
            switch self {
            case .ffmpegNotInstalled:
                return "ffmpeg isn't installed. Install it with `brew install ffmpeg` and try again."
            case .sourceMissing(let url):
                return "Source recording is missing: \(url.path)"
            case .ffmpegFailed(let stage, let code, let stderr):
                let snippet = stderr.split(separator: "\n").suffix(8).joined(separator: "\n")
                return "ffmpeg \(stage) failed (exit \(code)).\n\n\(snippet)"
            case .paletteMissing:
                return "ffmpeg produced no palette file. The recording may be empty or corrupt."
            }
        }
    }

    struct Options {
        var width: Int = 720
        var fps: Int = 15
    }

    /// Convert `source` (MP4) into a GIF at `destination`. Runs the two
    /// ffmpeg passes off the main queue. Safe to call from a Swift Task.
    static func convert(source: URL, destination: URL, options: Options = .init()) async throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw Error.sourceMissing(source)
        }
        guard let ffmpeg = locateFFmpeg() else {
            throw Error.ffmpegNotInstalled
        }

        let paletteURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("maczoomer-palette-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: paletteURL) }

        let paletteFilter =
            "fps=\(options.fps),scale=\(options.width):-1:flags=lanczos,palettegen=stats_mode=full"
        try await runFFmpeg(
            at: ffmpeg,
            arguments: [
                "-y",
                "-i", source.path,
                "-vf", paletteFilter,
                paletteURL.path
            ],
            stage: "palettegen"
        )
        guard FileManager.default.fileExists(atPath: paletteURL.path) else {
            throw Error.paletteMissing
        }

        let gifFilter =
            "fps=\(options.fps),scale=\(options.width):-1:flags=lanczos[x];[x][1:v]paletteuse=dither=sierra2_4a"
        try await runFFmpeg(
            at: ffmpeg,
            arguments: [
                "-y",
                "-i", source.path,
                "-i", paletteURL.path,
                "-filter_complex", gifFilter,
                destination.path
            ],
            stage: "paletteuse"
        )
    }

    private static func locateFFmpeg() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        // Fall back to `/usr/bin/env ffmpeg` so the user's PATH (login shell)
        // gets a chance.
        let env = Process()
        env.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        env.arguments = ["which", "ffmpeg"]
        let pipe = Pipe()
        env.standardOutput = pipe
        env.standardError = Pipe()
        do {
            try env.run()
            env.waitUntilExit()
            if env.terminationStatus == 0,
               let data = try? pipe.fileHandleForReading.readToEnd(),
               let path = String(data: data, encoding: .utf8)?
                   .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func runFFmpeg(at url: URL, arguments: [String], stage: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = url
                process.arguments = arguments
                let errPipe = Pipe()
                process.standardError = errPipe
                process.standardOutput = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let stderr = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(throwing: Error.ffmpegFailed(
                        stage: stage,
                        exitCode: process.terminationStatus,
                        stderr: stderr
                    ))
                }
            }
        }
    }
}
