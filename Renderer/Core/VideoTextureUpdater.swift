//
//  VideoTextureUpdater.swift
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

import AVFoundation
import CoreVideo
import Foundation
import MetalKit

class VideoTextureUpdater: @unchecked Sendable {
    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var texture: MTLTexture
    private var timer: Timer?
    private var videoURL: URL?

    init(url: URL, texture: MTLTexture) {
        self.texture = texture
        self.videoURL = url

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)

        let playerItem = AVPlayerItem(url: url)
        if let output = self.videoOutput {
            playerItem.add(output)
        }

        self.player = AVPlayer(playerItem: playerItem)
        self.player?.actionAtItemEnd = .none
        self.player?.isMuted = true
        self.player?.volume = 0.0

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loopVideo),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.updateTexture()
            }
            self.timer = t
            RunLoop.current.add(t, forMode: .common)
        }

        self.player?.play()
    }

    @objc private func loopVideo(notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              item == player?.currentItem else { return }
        item.seek(to: .zero, completionHandler: nil)
    }

    @objc private func updateTexture() {
        guard let output = videoOutput else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: time) {
            if let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

                if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                    let width = CVPixelBufferGetWidth(pixelBuffer)
                    let height = CVPixelBufferGetHeight(pixelBuffer)
                    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

                    let region = MTLRegionMake2D(
                        0,
                        0,
                        min(width, texture.width),
                        min(height, texture.height)
                    )
                    texture.replace(
                        region: region,
                        mipmapLevel: 0,
                        slice: 0,
                        withBytes: baseAddress,
                        bytesPerRow: bytesPerRow,
                        bytesPerImage: bytesPerRow * height
                    )
                }
            }
        }
    }

    func stop() {
        let t = timer
        timer = nil
        DispatchQueue.main.async {
            t?.invalidate()
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        NotificationCenter.default.removeObserver(self)
        
        if let url = videoURL {
            DispatchQueue.global(qos: .background).async {
                try? FileManager.default.removeItem(at: url)
            }
            videoURL = nil
        }
    }

    deinit {
        stop()
    }
}
