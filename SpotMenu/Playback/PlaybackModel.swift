import Combine
import SwiftUI

extension Notification.Name {
    static let contentModelDidUpdate = Notification.Name(
        "PlaybackModelDidUpdate"
    )
}

enum PlayerType {
    case spotify
    case appleMusic
}

enum LongFormTitleStyle: String, CaseIterable, Identifiable {
    case titleOnly
    case segmentOnly
    case titleAndSegment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .titleOnly: return "Title Only"
        case .segmentOnly: return "Chapter/Episode Only"
        case .titleAndSegment: return "Title + Chapter/Episode"
        }
    }
}

enum PreferredPlayer: String, CaseIterable, Identifiable {
    case automatic
    case spotify
    case appleMusic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        }
    }
}

enum LongFormKind {
    case audiobook
    case podcastEpisode
}

struct LongFormInfo {
    let kind: LongFormKind
    let title: String      // book or show title
    let authors: [String]  // authors or publisher
    let segmentTitle: String? // chapter or episode title
}

struct PlaybackInfo {
    let artist: String
    let title: String
    let isPlaying: Bool
    let imageURL: URL?
    let totalTime: Double
    let currentTime: Double
    let image: Image?
    let isLiked: Bool?
    let longFormInfo: LongFormInfo?
}

protocol MusicPlayerController {
    func fetchNowPlayingInfo() -> PlaybackInfo?
    func togglePlayPause()
    func skipForward()
    func skipBack()
    func updatePlaybackPosition(to seconds: Double)
    func openApp()
    func toggleLiked()
    func likeTrack()
    func unlikeTrack()
    /// The name AppleScript knows the player by ("Spotify", "Music").
    var appleScriptName: String { get }
}

// Spotify and Music share the same AppleScript verbs for these, so one implementation
// serves both. Each script checks `is running` first: `tell` would otherwise launch the app.
extension MusicPlayerController {
    func play() {
        _ = runAppleScript("tell application \"\(appleScriptName)\" to if it is running then play")
    }

    func pause() {
        _ = runAppleScript("tell application \"\(appleScriptName)\" to if it is running then pause")
    }

    /// The player's own volume, 0...100, or nil when the player isn't running.
    func volume() -> Int? {
        let script = """
            tell application "\(appleScriptName)"
                if it is running then return sound volume
            end tell
            """
        guard let text = runAppleScript(script) else { return nil }
        return Int(text)
    }

    func setVolume(_ percent: Int) {
        _ = runAppleScript(
            "tell application \"\(appleScriptName)\" to if it is running then set sound volume to \(percent)"
        )
    }
}

class PlaybackModel: ObservableObject {
    @Published var imageURL: URL?
    @Published var image: Image? = nil
    @Published var isPlaying: Bool = false
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var totalTime: Double = 1
    @Published var currentTime: Double = 0
    @Published var playerType: PlayerType
    @Published var isLiked: Bool? = nil
    @Published var longFormInfo: LongFormInfo? = nil
    /// The player's volume, 0...100; nil when the player isn't running.
    @Published var volume: Int? = nil

    private let preferences: MusicPlayerPreferencesModel
    /// After we set the volume, polls keep our value until this time, so a poll that
    /// raced the change doesn't snap the slider back.
    private var volumeHeldUntil = Date.distantPast
    private var controller: MusicPlayerController
    private var timer: Timer?

    private var cancellable: AnyCancellable?

    var playerIconName: String {
        return playerType == .appleMusic ? "AppleMusicIcon" : "SpotifyIcon"
    }

    var isLikingImplemented: Bool {
        return playerType == .spotify
    }

    init(preferences: MusicPlayerPreferencesModel) {
        self.preferences = preferences

        let (controller, type) = Self.selectController(
            for: preferences.preferredMusicApp,
            preferences: preferences
        )
        self.controller = controller
        self.playerType = type

        fetchInfo()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            self.fetchInfo()
        }

        cancellable = preferences.$preferredMusicApp
            .removeDuplicates()
            .sink { [weak self] newPreference in
                self?.switchPlayer(to: newPreference)
            }
    }

    func switchPlayer(to newPreference: PreferredPlayer) {
        let (newController, newType) = Self.selectController(
            for: newPreference,
            preferences: preferences
        )
        controller = newController
        playerType = newType
        fetchInfo()
    }

    private static func selectController(
        for preference: PreferredPlayer,
        preferences: MusicPlayerPreferencesModel
    ) -> (
        MusicPlayerController, PlayerType
    ) {
        let spotifyInstalled = isAppInstalled("com.spotify.client")
        let appleMusicInstalled = isAppInstalled("com.apple.Music")
        let spotifyRunning = isAppRunning("com.spotify.client")
        let appleMusicRunning = isAppRunning("com.apple.Music")

        switch preference {
        case .appleMusic:
            return (AppleMusicController(), .appleMusic)
        case .spotify:
            return (SpotifyController(preferences: preferences), .spotify)
        case .automatic:
            if spotifyRunning {
                return (SpotifyController(preferences: preferences), .spotify)
            } else if appleMusicRunning {
                return (AppleMusicController(), .appleMusic)
            } else if spotifyInstalled {
                return (SpotifyController(preferences: preferences), .spotify)
            } else if appleMusicInstalled {
                return (AppleMusicController(), .appleMusic)
            } else {
                return (SpotifyController(preferences: preferences), .spotify)
            }
        }
    }

    private static func isAppInstalled(_ bundleIdentifier: String) -> Bool {
        return NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) != nil
    }

    private static func isAppRunning(_ bundleIdentifier: String) -> Bool {
        return NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).count > 0
    }

    func fetchInfo() {
        guard let info = controller.fetchNowPlayingInfo() else {
            reset()
            return
        }

        let displayText = computeDisplayText(from: info)
        let polledVolume = controller.volume()

        DispatchQueue.main.async {
            if Date() >= self.volumeHeldUntil {
                self.volume = polledVolume
            }
            self.title = displayText.title
            self.artist = displayText.artist
            self.isPlaying = info.isPlaying
            self.imageURL = info.imageURL
            self.totalTime = info.totalTime
            self.currentTime = info.currentTime
            self.image = info.image
            self.isLiked = info.isLiked
            self.longFormInfo = info.longFormInfo

            NotificationCenter.default.post(
                name: .contentModelDidUpdate,
                object: nil
            )
        }
    }

    func togglePlayPause() {
        // Execute the command first
        controller.togglePlayPause()
        
        // Small delay to allow the music player to process, then update UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.isPlaying.toggle()
            self.notifyModelUpdate()
        }
        
        delayedFetch()
    }

    /// Explicit play/pause (not toggles) for the call watcher, which must never flip
    /// the state the wrong way if a poll is stale.
    func play() {
        controller.play()
        isPlaying = true
        notifyModelUpdate()
        delayedFetch()
    }

    func pause() {
        controller.pause()
        isPlaying = false
        notifyModelUpdate()
        delayedFetch()
    }

    func setVolume(_ percent: Int) {
        let clamped = max(0, min(100, percent))
        volume = clamped
        volumeHeldUntil = Date().addingTimeInterval(1.5)
        controller.setVolume(clamped)
    }

    /// Moves the volume by `delta` points; returns the new level, or nil when the
    /// player isn't running.
    @discardableResult
    func nudgeVolume(by delta: Int) -> Int? {
        guard let current = volume ?? controller.volume() else { return nil }
        setVolume(current + delta)
        return volume
    }

    func skipForward() {
        controller.skipForward()
        delayedFetch()
    }

    func skipBack() {
        controller.skipBack()
        delayedFetch()
    }

    func toggleLiked() {
        let previousLikeStatus = self.isLiked

        // Immediately update like status for UI responsiveness
        if let previous = previousLikeStatus {
            isLiked = !previous
        }
        
        // Send notification to update status bar immediately
        notifyModelUpdate()

        controller.toggleLiked()
        delayedFetch()
    }

    func likeTrack() {
        // Immediately update like status for UI responsiveness
        isLiked = true
        
        // Send notification to update status bar immediately
        notifyModelUpdate()
        
        controller.likeTrack()
    }

    func unlikeTrack() {
        // Immediately update like status for UI responsiveness
        isLiked = false
        
        // Send notification to update status bar immediately
        notifyModelUpdate()
        
        controller.unlikeTrack()
    }

    func updatePlaybackPosition(to seconds: Double) {
        controller.updatePlaybackPosition(to: seconds)
        self.currentTime = seconds
    }

    func openMusicApp() {
        controller.openApp()
    }

    private func delayedFetch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.fetchInfo()
        }
    }
    
    private func notifyModelUpdate() {
        NotificationCenter.default.post(
            name: .contentModelDidUpdate,
            object: nil
        )
    }

    private func reset() {
        DispatchQueue.main.async {
            self.title = ""
            self.artist = ""
            self.isPlaying = false
            self.imageURL = nil
            self.currentTime = 0
            self.totalTime = 1
            self.image = nil
            self.longFormInfo = nil
            self.volume = nil
        }
    }

    private func computeDisplayText(from info: PlaybackInfo)
        -> (artist: String, title: String)
    {
        guard let longFormInfo = info.longFormInfo else {
            return (info.artist, info.title)
        }

        let authorText = longFormInfo.authors.joined(separator: ", ")
        let baseTitle =
            longFormInfo.title.isEmpty ? info.title : longFormInfo.title
        let segmentTitle = longFormInfo.segmentTitle?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let titleText: String
        switch preferences.longFormTitleStyle {
        case .titleOnly:
            titleText = baseTitle
        case .segmentOnly:
            titleText = segmentTitle?.isEmpty == false ? segmentTitle!
                : baseTitle
        case .titleAndSegment:
            if let segment = segmentTitle,
                !segment.isEmpty,
                segment.caseInsensitiveCompare(baseTitle) != .orderedSame
            {
                titleText = "\(baseTitle) — \(segment)"
            } else {
                titleText = baseTitle
            }
        }

        let artistText = authorText.isEmpty ? info.artist : authorText

        return (artistText, titleText)
    }
}

func runAppleScript(_ script: String) -> String? {
    var error: NSDictionary?
    if let scriptObject = NSAppleScript(source: script) {
        let output = scriptObject.executeAndReturnError(&error)
        return output.stringValue
    }
    return nil
}

func openApp(bundleIdentifier: String) {
    guard
        let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        )
    else {
        print("App with bundle ID \(bundleIdentifier) not found.")
        return
    }

    let config = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.openApplication(at: url, configuration: config) {
        app,
        error in
        if let error = error {
            print("Failed to open app: \(error.localizedDescription)")
        }
    }
}
