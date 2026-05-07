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

    // MARK: - Player
    private let player: AVPlayer = {
        if let url = Bundle.main.url(forResource: "TeaseDSD", withExtension: "mp4") {
            return AVPlayer(url: url)
        }
        return AVPlayer()
    }()

    // Unified publisher for player item status (prevents Combine type mismatch)
    private var videoStatusPublisher: AnyPublisher<AVPlayerItem.Status, Never> {
        if let item = player.currentItem {
            return item.publisher(for: \.status).eraseToAnyPublisher()
        } else {
            return Just(AVPlayerItem.Status.unknown).eraseToAnyPublisher()
        }
    }

    // MARK: - Derived
    private var showIntroVideo: Bool {
        !hasPlayedVideo
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
        if player.currentItem == nil {
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
                    endVideo()
                }
                .onReceive(videoStatusPublisher) { status in
                    switch status {
                    case .readyToPlay:
                        isVideoLoading = false
                    case .failed:
                        showError = true
                        endVideo()
                    default:
                        break
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .ignoresSafeArea()
        }
    }

    // MARK: - Video Control
    private func startVideoIfNeeded() {
        guard !hasPlayedVideo else { return }
        guard player.currentItem != nil else {
            showError = true
            return
        }
        isVideoLoading = true
        setupAudio()
        player.seek(to: .zero)
        player.play()
    }

    // MARK: - Audio
    private func setupAudio() {
        // AVAudioSession operations should be on main thread.
        DispatchQueue.main.async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            } catch {
                // Silently handle audio session errors
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
