//
//  VideoIntroController.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/26/25.
//


import Foundation
@preconcurrency import AVFoundation
import Combine
import SwiftUI

@MainActor
final class VideoIntroController: ObservableObject {

    // MARK: Public Published State
    @Published var isLoading = true
    @Published var hasVideo = false          // true if a playable (ready & frames) track is present
    @Published var playbackFinished = false
    @Published var playbackFailed = false
    @Published var showSkip = false
    @Published var muted = false
    @Published var debugMessages: [String] = []

    // MARK: Configuration
    let autoSkipAfterSeconds: Double = 12        // Failsafe ceiling
    let minDisplaySeconds: Double = 0.75         // Ensure we don't skip too fast
    let giveUpIfNoFrameSeconds: Double = 2.0     // If no presentationSize after this -> fallback
    let showSkipAfterSeconds: Double = 1.2       // Delay before Skip button appears
    let enableDebugLogging: Bool = true

    // Provide your resource name & extension
    private let videoName: String
    private let videoExtension: String

    // Expose player for the layer view
    let player: AVPlayer
    private var cancellables = Set<AnyCancellable>()
    private var startedAt: Date?
    private var frameCheckFired = false
    private var endTriggered = false

    init(videoName: String = "TeaseDSD",
         videoExtension: String = "mp4",
         autoplay: Bool = true) {

        self.videoName = videoName
        self.videoExtension = videoExtension

        if let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension) {
            self.player = AVPlayer(url: url)
        } else {
            self.player = AVPlayer()
            log("Resource \(videoName).\(videoExtension) NOT found in bundle.")
            playbackFailed = true
            isLoading = false
            hasVideo = false
            return
        }

        observeItemStatus()
        observeTimeControl()
        // Optionally observe rate:
        player.publisher(for: \.rate)
            .sink { [weak self] r in self?.log("rate=\(r)") }
            .store(in: &cancellables)

        if autoplay {
            start()
        }
    }

    // MARK: Start
    func start() {
        guard !playbackFinished && !playbackFailed else { return }
        isLoading = true
        startedAt = Date()
        player.seek(to: .zero)
        player.play()
        scheduleSkipVisibility()
        scheduleNoFrameFallback()
        scheduleAutoSkipSafety()
    }

    func toggleMute() {
        muted.toggle()
        player.isMuted = muted
    }

    // MARK: Internal Observations
    private func observeItemStatus() {
        player.publisher(for: \.currentItem?.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] statusOpt in
                guard let self else { return }
                guard let status = statusOpt else { return }
                switch status {
                case .readyToPlay:
                    log("Item readyToPlay.")
                    // remain loading until we confirm a frame/presentation size
                case .failed:
                    log("Item failed: \(String(describing: self.player.currentItem?.error))")
                    markFailure()
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func observeTimeControl() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] tcs in
                self?.log("timeControlStatus=\(tcs.rawValue) (0=paused,1=waiting,2=playing)")
                if tcs == .playing {
                    // Potentially first frame soon; check presentation size
                    self?.checkPresentationSize()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Presentation Size / Frame Check
    func checkPresentationSize() {
        guard let item = player.currentItem else { return }
        let size = item.presentationSize
        if size != .zero {
            if !frameCheckFired {
                frameCheckFired = true
                log("First non-zero presentationSize=\(size)")
                hasVideo = true
                isLoading = false
            }
        } else {
            // Recheck a bit later until fallback timer triggers
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.checkPresentationSize()
            }
        }
    }

    private func scheduleNoFrameFallback() {
        DispatchQueue.main.asyncAfter(deadline: .now() + giveUpIfNoFrameSeconds) { [weak self] in
            guard let self else { return }
            if !self.frameCheckFired && !self.playbackFailed && !self.playbackFinished {
                self.log("No frame after \(self.giveUpIfNoFrameSeconds)s → fallback.")
                self.markFailure()
                self.finish(force: true)
            }
        }
    }

    private func scheduleAutoSkipSafety() {
        DispatchQueue.main.asyncAfter(deadline: .now() + autoSkipAfterSeconds) { [weak self] in
            guard let self else { return }
            if !self.playbackFinished {
                self.log("Auto-safety skip after \(self.autoSkipAfterSeconds)s")
                self.finish(force: true)
            }
        }
    }

    private func scheduleSkipVisibility() {
        DispatchQueue.main.asyncAfter(deadline: .now() + showSkipAfterSeconds) { [weak self] in
            guard let self else { return }
            if !self.playbackFinished && !self.playbackFailed {
                self.showSkip = true
            }
        }
    }

    // MARK: Public Actions
    func userSkip() {
        log("User tapped Skip.")
        finish(force: true)
    }

    func playbackEndedNaturally() {
        log("Playback ended naturally.")
        finish(force: false)
    }

    // MARK: Finish
    private func finish(force: Bool) {
        guard !endTriggered else { return }
        endTriggered = true
        player.pause()
        playbackFinished = true
    }

    private func markFailure() {
        playbackFailed = true
        hasVideo = false
        isLoading = false
    }

    private func log(_ msg: String) {
        guard enableDebugLogging else { return }
        debugMessages.append(msg)
        print("[VideoIntro] \(msg)")
    }
}
