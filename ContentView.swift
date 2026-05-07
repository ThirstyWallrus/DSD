//
//  ContentView.swift
//  DynastyStatDrop / DSD
//

import SwiftUI
import AVKit
@preconcurrency import AVFoundation
import Combine

struct ContentView: View {

    // MARK: - Environment
    @EnvironmentObject var authViewModel: AuthViewModel

    // MARK: - Intro / Video State
    @State private var hasPlayedVideo = false
    @State private var isVideoLoading = false
    @State private var showError = false
    @State private var isMuted = false
    @State private var logoOpacity = 0.0
    @State private var selectedTab: Tab = .dashboard

    // Optional: track if first frame appeared (for fallback)
    @State private var firstFrameConfirmed = false

    // MARK: - Configuration
    private let DEBUG_VIDEO = true
    private let fallbackIfNoFrameAfter: TimeInterval = 2.0   // Set to 0 to disable

    // Uncomment to bypass intro on simulator during rapid dev cycles
    #if targetEnvironment(simulator)
    private let SKIP_VIDEO_ON_SIMULATOR = false  // Set to true to skip video on simulator during testing
    #else
    private let SKIP_VIDEO_ON_SIMULATOR = false
    #endif

    // MARK: - Player
    private let player: AVPlayer = {
        if let url = Bundle.main.url(forResource: "TeaseDSD", withExtension: "mp4") {
            return AVPlayer(url: url)
        }
        return AVPlayer()
    }()

    // Unified publisher for player item status (prevents Combine type mismatch)
    private var videoStatusPublisher: AnyPublisher {
        if let item = player.currentItem {
            return item.publisher(for: \.status).eraseToAnyPublisher()
        } else {
            return Just(AVPlayerItem.Status.unknown).eraseToAnyPublisher()
        }
    }

    // MARK: - Derived
    private var showIntroVideo: Bool {
        !hasPlayedVideo && !SKIP_VIDEO_ON_SIMULATOR
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                // Show intro video if not yet played
                if showIntroVideo {
                    introVideoLayer
                        .transition(.opacity)
                }

                // Show logo during/after video
                Image("DynastyStatDropLogo")
                    .resizable()
                    .scaledToFit()
                    .adaptiveLogo(max: 500, screenFraction: 0.9)
                    .opacity(logoOpacity)
                    .animation(.easeInOut(duration: 0.8), value: logoOpacity)

                // After video finishes, show appropriate auth view
                if hasPlayedVideo {
                    if authViewModel.isLoggedIn {
                        MainTabView()
                            .transition(.opacity)
                    } else {
                        SignIn()
                            .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .onAppear {
                handleOnAppear()
            }
        }
    }

    // MARK: - On Appear
    private func handleOnAppear() {
        // Check if simulator skip is enabled
        if SKIP_VIDEO_ON_SIMULATOR {
            log("[VideoDebug] Simulator skip active; bypassing video.")
            endVideo()
            return
        }

        if player.currentItem == nil {
            log("[VideoDebug] Resource TeaseDSD.mp4 not found in bundle.")
            showError = true
            endVideo()
        }
    }

    // MARK: - Video Layer
    private var introVideoLayer: some View {
        ZStack {
            videoPlayerContainer

            if isVideoLoading {
                ProgressView().tint(.white.opacity(0.7))
            }

            // Skip button
            VStack {
                HStack {
                    Spacer()
                    Button("Skip", action: endVideo)
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(8)
                        .padding(.top, 30)
                        .padding(.trailing, 24)
                }
                Spacer()
            }

            if showError {
                Text("Video unavailable")
                    .foregroundColor(.white.opacity(0.75))
                    .font(.caption)
                    .padding(10)
                    .background(Color.black.opacity(0.4).cornerRadius(8))
            }
        }
    }

    private var videoPlayerContainer: some View {
        GeometryReader { geo in
            VideoPlayer(player: player)
                .onAppear { startVideoIfNeeded() }
                .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                    log("[VideoDebug] Playback finished.")
                    endVideo()
                }
                .onReceive(videoStatusPublisher) { status in
                    switch status {
                    case .readyToPlay:
                        log("[VideoDebug] Item readyToPlay.")
                        isVideoLoading = false
                        // Only do deep inspection when debugging
                        if DEBUG_VIDEO {
                            testFirstFrame()
                        }
                    case .failed:
                        log("[VideoDebug] Item failed: \(String(describing: player.currentItem?.error))")
                        showError = true
                        endVideo()
                    default:
                        break
                    }
                }
                .onReceive(player.publisher(for: \.timeControlStatus)) { tcs in
                    log("[VideoDebug] timeControlStatus=\(tcs.rawValue)") // 0=paused,1=waiting,2=playing
                    if tcs == .playing && !firstFrameConfirmed {
                        // We rely on frame extraction test to confirm actual rendering
                        checkPresentationSize()
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .ignoresSafeArea()
        }
    }

    // MARK: - Video Control / Debug
    private func startVideoIfNeeded() {
        guard !hasPlayedVideo else { return }
        guard player.currentItem != nil else {
            showError = true
            log("[VideoDebug] startVideoIfNeeded: currentItem nil (resource missing or init failure).")
            return
        }
        isVideoLoading = true
        setupAudio()
        player.seek(to: .zero)
        player.play()
        scheduleNoFrameFallbackIfNeeded()
    }

    private func scheduleNoFrameFallbackIfNeeded() {
        guard fallbackIfNoFrameAfter > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + fallbackIfNoFrameAfter) {
            if !hasPlayedVideo && !firstFrameConfirmed {
                log("[VideoDebug] No first frame after \(fallbackIfNoFrameAfter)s — fallback endVideo().")
                showError = true
                endVideo()
            }
        }
    }

    private func checkPresentationSize() {
        guard let item = player.currentItem else { return }
        let size = item.presentationSize
        if size != .zero {
            if !firstFrameConfirmed {
                firstFrameConfirmed = true
                log("[VideoDebug] First non-zero presentationSize=\(size)")
            }
        } else {
            // Recheck a bit later until fallback timer triggers
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.checkPresentationSize()
            }
        }
    }

    private func testFirstFrame() {
        guard let asset = player.currentItem?.asset else { return }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let t = CMTime(seconds: 0.1, preferredTimescale: 600)
        DispatchQueue.global().async {
            do {
                let cg = try gen.copyCGImage(at: t, actualTime: nil)
                DispatchQueue.main.async {
                    self.firstFrameConfirmed = true
                    self.log("[FrameTest] Extracted frame: \(cg.width)x\(cg.height)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("[FrameTest] Frame extract error: \(error)")
                }
            }
        }
    }

    private func log(_ message: String) {
        if DEBUG_VIDEO { print(message) }
    }

    // MARK: - Audio
    private func setupAudio() {
        // AVAudioSession operations should be on main thread.
        DispatchQueue.main.async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            } catch {
                self.log("[VideoDebug] Audio session setCategory error: \(error)")
            }
            self.player.isMuted = self.isMuted
        }
    }

    // MARK: - End / Transition
    private func endVideo() {
        guard !hasPlayedVideo else { return }
        player.pause()
        hasPlayedVideo = true
        withAnimation(.easeInOut(duration: 1.0)) { logoOpacity = 1.0 }
        // Logo stays visible while auth view transitions in
    }
}
