import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

private struct Options {
    var bundleIdentifier = "com.tibia.client"
    var processID: pid_t?
    var output = URL(fileURLWithPath: "official-client-capture.mov")
    var metadata = URL(fileURLWithPath: "official-client-capture.json")
    var duration: TimeInterval = 60
    var width = 1280
    var height = 720

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var metadataWasSpecified = false
        var index = 0

        func value(after flag: String) throws -> String {
            guard index + 1 < arguments.count else {
                throw CaptureError.usage("missing value after \(flag)")
            }
            index += 1
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--bundle-id":
                options.bundleIdentifier = try value(after: argument)
            case "--pid":
                guard let value = Int32(try value(after: argument)) else {
                    throw CaptureError.usage("--pid expects an integer")
                }
                options.processID = value
            case "--output":
                options.output = URL(fileURLWithPath: try value(after: argument)).standardizedFileURL
            case "--metadata":
                options.metadata = URL(fileURLWithPath: try value(after: argument)).standardizedFileURL
                metadataWasSpecified = true
            case "--duration":
                guard let value = Double(try value(after: argument)), value > 0 else {
                    throw CaptureError.usage("--duration expects a positive number of seconds")
                }
                options.duration = value
            case "--width":
                guard let value = Int(try value(after: argument)), value > 0 else {
                    throw CaptureError.usage("--width expects a positive integer")
                }
                options.width = value
            case "--height":
                guard let value = Int(try value(after: argument)), value > 0 else {
                    throw CaptureError.usage("--height expects a positive integer")
                }
                options.height = value
            case "--help", "-h":
                throw CaptureError.help
            default:
                throw CaptureError.usage("unknown argument: \(argument)")
            }
            index += 1
        }

        if !metadataWasSpecified {
            options.metadata = options.output.deletingPathExtension().appendingPathExtension("json")
        }
        return options
    }
}

private enum CaptureError: Error, CustomStringConvertible {
    case help
    case usage(String)
    case applicationNotFound(String)
    case displayNotFound
    case writer(String)

    var description: String {
        switch self {
        case .help:
            return ""
        case .usage(let message), .writer(let message):
            return message
        case .applicationNotFound(let identity):
            return "no on-screen application matched \(identity); start the client first"
        case .displayNotFound:
            return "ScreenCaptureKit did not expose a display"
        }
    }
}

private let usage = """
Usage: sound-parity-capture [options]

Records one application's video and audio on the same ScreenCaptureKit clock.

  --bundle-id ID    application bundle id (default: com.tibia.client)
  --pid PID         select an exact running process instead of bundle id
  --output PATH     MOV output (default: official-client-capture.mov)
  --metadata PATH   JSON clock/process metadata (defaults beside MOV)
  --duration SEC    capture duration (default: 60)
  --width PIXELS    encoded width (default: 1280)
  --height PIXELS   encoded height (default: 720)
"""

private struct CaptureMetadata: Codable {
    let schema: String
    let bundleIdentifier: String
    let applicationName: String
    let processID: Int32
    let startedEpochUs: UInt64
    let firstSampleEpochUs: UInt64
    let endedEpochUs: UInt64
    let durationSeconds: Double
    let movie: String
    let videoWidth: Int
    let videoHeight: Int
    let audioSampleRate: Int
    let audioChannels: Int
}

private final class CaptureWriter: NSObject, SCStreamOutput, SCStreamDelegate {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let lock = NSLock()
    private var sessionStarted = false
    private var sessionStartTime = CMTime.invalid
    private var lastVideoTime = CMTime.invalid
    private var lastAudioTime = CMTime.invalid
    private(set) var firstSampleEpochUs: UInt64 = 0
    private var failedError: Error?

    init(output: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: output)
        do {
            writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        } catch {
            throw CaptureError.writer("cannot create \(output.path): \(error)")
        }

        videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoExpectedSourceFrameRateKey: 60,
                ],
            ]
        )
        videoInput.expectsMediaDataInRealTime = true

        audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ]
        )
        audioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw CaptureError.writer("AVAssetWriter refused the capture inputs")
        }
        writer.add(videoInput)
        writer.add(audioInput)
        super.init()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        failedError = error
        lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        lock.lock()
        defer { lock.unlock() }

        if !sessionStarted {
            guard writer.startWriting() else {
                failedError = writer.error ?? CaptureError.writer("AVAssetWriter could not start")
                return
            }
            sessionStartTime = sampleBuffer.presentationTimeStamp
            writer.startSession(atSourceTime: sessionStartTime)
            firstSampleEpochUs = UInt64(Date().timeIntervalSince1970 * 1_000_000)
            sessionStarted = true
        }

        let presentationTime = sampleBuffer.presentationTimeStamp
        guard presentationTime.isValid,
              CMTimeCompare(presentationTime, sessionStartTime) >= 0 else { return }

        switch outputType {
        case .screen where videoInput.isReadyForMoreMediaData:
            guard !lastVideoTime.isValid || CMTimeCompare(presentationTime, lastVideoTime) > 0 else { return }
            if !videoInput.append(sampleBuffer) {
                failedError = writer.error
            } else {
                lastVideoTime = presentationTime
            }
        case .audio where audioInput.isReadyForMoreMediaData:
            guard !lastAudioTime.isValid || CMTimeCompare(presentationTime, lastAudioTime) > 0 else { return }
            if !audioInput.append(sampleBuffer) {
                failedError = writer.error
            } else {
                lastAudioTime = presentationTime
            }
        default:
            break
        }
    }

    func finish() async throws {
        let (started, error) = lock.withLock { (sessionStarted, failedError) }

        if let error { throw error }
        guard started else { throw CaptureError.writer("capture produced no samples") }

        videoInput.markAsFinished()
        audioInput.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        if let error = writer.error { throw error }
    }
}

@main
private struct SoundParityCapture {
    static func main() async {
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            try await capture(options)
        } catch CaptureError.help {
            print(usage)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n\n\(usage)\n".utf8))
            exit(2)
        }
    }

    private static func capture(_ options: Options) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let application = content.applications.first { application in
            if let processID = options.processID {
                return application.processID == processID
            }
            return application.bundleIdentifier == options.bundleIdentifier
        }
        guard let application else {
            throw CaptureError.applicationNotFound(options.processID.map(String.init) ?? options.bundleIdentifier)
        }
        guard let display = content.displays.first else { throw CaptureError.displayNotFound }

        try FileManager.default.createDirectory(
            at: options.output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: options.metadata.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = options.width
        configuration.height = options.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true

        let writer = try CaptureWriter(output: options.output, width: options.width, height: options.height)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: writer)
        let videoQueue = DispatchQueue(label: "sound-parity.capture.video", qos: .userInitiated)
        let audioQueue = DispatchQueue(label: "sound-parity.capture.audio", qos: .userInitiated)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: audioQueue)

        let startedEpochUs = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        print("capturing \(application.applicationName) (pid \(application.processID)) for \(options.duration)s")
        print("movie: \(options.output.path)")
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(options.duration))
        try await stream.stopCapture()
        try await writer.finish()
        let endedEpochUs = UInt64(Date().timeIntervalSince1970 * 1_000_000)

        let metadata = CaptureMetadata(
            schema: "crystal-sound-capture-v1",
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.applicationName,
            processID: application.processID,
            startedEpochUs: startedEpochUs,
            firstSampleEpochUs: writer.firstSampleEpochUs,
            endedEpochUs: endedEpochUs,
            durationSeconds: Double(endedEpochUs - startedEpochUs) / 1_000_000,
            movie: options.output.path,
            videoWidth: options.width,
            videoHeight: options.height,
            audioSampleRate: 48_000,
            audioChannels: 2
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: options.metadata, options: .atomic)
        print("metadata: \(options.metadata.path)")
    }
}
