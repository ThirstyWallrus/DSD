//
//  PlayerLayerView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/26/25.
//


import SwiftUI
import AVFoundation
import AVKit

// A simple UIViewRepresentable that exposes an AVPlayerLayer for reliable rendering
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    class PlayerLayerHostingView: UIView {
        private let playerLayer = AVPlayerLayer()

        init(player: AVPlayer) {
            super.init(frame: .zero)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            layer.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }

    func makeUIView(context: Context) -> PlayerLayerHostingView {
        PlayerLayerHostingView(player: player)
    }

    func updateUIView(_ uiView: PlayerLayerHostingView, context: Context) {
        // Nothing dynamic needed; if you wanted to toggle gravity you could do it here.
    }
}