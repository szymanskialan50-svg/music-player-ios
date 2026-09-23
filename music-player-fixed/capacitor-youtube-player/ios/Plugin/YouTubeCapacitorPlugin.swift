import Foundation
import Capacitor
import WebKit

import AVFoundation

@objc(YouTubeCapacitorPlugin)
public class YouTubeCapacitorPlugin: CAPPlugin {
    
    private var player: YouTubePlayer?
    private var timer: Timer?
    
    public override func load() {
        super.load()
        DispatchQueue.main.async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to set audio session category.")
            }
            
            self.player = YouTubePlayer()
            
            // Add the player's web view as a hidden subview to the Capacitor web view
            // so it can play audio in the background without taking up screen space.
            if let webView = self.player?.webView {
                webView.isHidden = true
                self.bridge?.webView?.superview?.addSubview(webView)
            }
        }
    }
    
    @objc func load(_ call: CAPPluginCall) {
        let videoId = call.getString("videoId") ?? ""
        
        DispatchQueue.main.async {
            if self.player?.webView == nil {
                // In case it wasn't initialized yet
                self.player?.load(videoId: videoId)
                if let webView = self.player?.webView {
                    webView.isHidden = true
                    self.bridge?.webView?.superview?.addSubview(webView)
                }
            } else {
                self.player?.load(videoId: videoId)
            }
            
            self.startStateObserver()
            call.resolve()
        }
    }
    
    @objc func play(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.player?.play()
            call.resolve()
        }
    }
    
    @objc func pause(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.player?.pause()
            call.resolve()
        }
    }
    
    @objc func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.player?.stop()
            self.stopStateObserver()
            call.resolve()
        }
    }
    
    @objc func seekTo(_ call: CAPPluginCall) {
        let seconds = call.getFloat("seconds") ?? 0
        DispatchQueue.main.async {
            self.player?.seekTo(seconds, allowSeekAhead: true)
            call.resolve()
        }
    }
    
    @objc func setVolume(_ call: CAPPluginCall) {
        // IFrame API volume controls are not directly exposed by YouTubePlayer in this version,
        // but it doesn't matter much since iOS manages volume via hardware buttons.
        call.resolve()
    }
    
    private func startStateObserver() {
        stopStateObserver()
        
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.notifyState()
            }
        }
    }
    
    private func stopStateObserver() {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
        }
    }
    
    private func notifyState() {
        guard let player = self.player else { return }
        
        let stateStr: String
        switch player.playerState {
        case .unstarted: stateStr = "unstarted"
        case .ended: stateStr = "ended"
        case .playing: stateStr = "playing"
        case .paused: stateStr = "paused"
        case .buffering: stateStr = "buffering"
        case .cued: stateStr = "cued"
        case .unknown: stateStr = "unknown"
        }
        
        self.notifyListeners("youtubeStateChange", data: ["state": stateStr])
        
        Task {
            do {
                let duration = try await player.duration()
                let currentTime = try await player.currentTime()
                
                self.notifyListeners("youtubeTimeUpdate", data: [
                    "currentTime": currentTime,
                    "duration": duration
                ])
            } catch {
                // Ignore
            }
        }
    }
}
