//
//  SongPreviewPlayer.swift
//  ITBizEnglish
//
//  Plays the 30-second song preview from a SongResult's previewURL. Observable
//  so views can show a play/pause state per song; only one preview plays at a
//  time and it auto-resets when the clip finishes.
//

import AVFoundation
import Observation

@Observable
final class SongPreviewPlayer {
    /// The id of the song whose preview is currently playing, else nil.
    private(set) var playingID: Int?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    /// Toggles: starts `song`'s preview, or stops it if it's already playing.
    func toggle(_ song: SongResult) {
        guard let url = song.previewURL else { return }
        if playingID == song.id { stop(); return }
        stop()

        configureSession()
        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.stop() }

        let p = AVPlayer(playerItem: item)
        player = p
        playingID = song.id
        p.play()
    }

    func stop() {
        player?.pause()
        player = nil
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        playingID = nil
    }

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    deinit {
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }
    }
}
