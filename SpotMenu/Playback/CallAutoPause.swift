import Combine
import CoreAudio
import CoreMediaIO
import Foundation
import os

/// Pauses the player when a call starts and resumes it when the call ends.
///
/// Rules, in order of who wins:
/// - It only pauses music that is playing, and only resumes music it paused itself.
/// - If you press play during the call, the call is yours: it won't touch playback again
///   until the next call.
/// - The call has to stay over for `resumeGrace` before music comes back, so a mic that
///   blinks off for a moment (switching devices, a dropped Bluetooth link) doesn't
///   start the music mid-call.
final class CallAutoPause: ObservableObject {
    /// True while the music is paused because of a call; the menu bar shows this.
    @Published private(set) var pausedForCall = false

    static let resumeGrace: TimeInterval = 5
    private let log = Logger(subsystem: "codes.charlie.spotmenu", category: "calls")

    private let playback: PlaybackModel
    private let preferences: MusicPlayerPreferencesModel
    private var timer: Timer?
    private var inCall = false
    private var quietSince: Date?

    init(playback: PlaybackModel, preferences: MusicPlayerPreferencesModel) {
        self.playback = playback
        self.preferences = preferences
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        step(callSignal: CallSignals.inCall(), now: Date())
    }

    private func step(callSignal: Bool, now: Date) {
        if callSignal {
            quietSince = nil
            if !inCall {
                inCall = true
                let pausing = preferences.pauseDuringCalls && playback.isPlaying
                log.notice("call started; playing=\(self.playback.isPlaying) pausing=\(pausing)")
                if pausing {
                    playback.pause()
                    pausedForCall = true
                }
            }
        } else if inCall {
            let since = quietSince ?? now
            quietSince = since
            if now.timeIntervalSince(since) >= Self.resumeGrace {
                inCall = false
                quietSince = nil
                log.notice("call ended; resuming=\(self.pausedForCall && self.preferences.resumeAfterCalls)")
                if pausedForCall {
                    pausedForCall = false
                    if preferences.resumeAfterCalls && !playback.isPlaying {
                        playback.play()
                    }
                }
            }
        }

        // You pressed play mid-call: stop managing this call.
        if pausedForCall && playback.isPlaying {
            log.notice("play pressed during the call; leaving it alone")
            pausedForCall = false
        }
    }
}

/// Whether a call looks to be in progress: any audio input device is capturing, or any
/// camera is running. App-agnostic (Zoom, Meet, Teams, FaceTime, huddles) and
/// device-agnostic (every input, so AirPods and interfaces count). Pure reads of public
/// device properties: nothing is captured. Taken from pace's Signals.swift.
///
/// Gap: muted with the camera off, where the call app has closed the mic, reads as no call.
enum CallSignals {
    static func inCall() -> Bool { anyInputRunning() || anyCameraRunning() }

    private static func anyInputRunning() -> Bool {
        audioDevices().contains { hasInputChannels($0) && isRunningSomewhere($0) }
    }

    private static func audioDevices() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    private static func hasInputChannels(_ device: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0
        else { return false }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr
        else { return false }
        let list = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    private static func anyCameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0
        else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == noErr
        else { return false }

        var runAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        for id in ids {
            var running: UInt32 = 0
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(
                id, &runAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == noErr,
                running != 0
            {
                return true
            }
        }
        return false
    }
}
