#!/usr/bin/env swift

import Foundation

// Define the necessary types and functions from MediaRemote framework
typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping (CFDictionary) -> Void) -> Void

// Load the MediaRemote framework dynamically
guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
      let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) else {
    // Failed to load MediaRemote framework
    exit(1)
}

let MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(MRMediaRemoteGetNowPlayingInfoPointer, to: MRMediaRemoteGetNowPlayingInfoFunction.self)

// Create a dispatch group for synchronization
let group = DispatchGroup()
var nowPlayingInfo: [String: Any]?

group.enter()

// Get now playing info - try using global queue instead of main
MRMediaRemoteGetNowPlayingInfo(DispatchQueue.global()) { info in
    nowPlayingInfo = info as? [String: Any]
    group.leave()
}

// Wait for the callback (with timeout)
let result = group.wait(timeout: .now() + 5)
if result == .timedOut {
    exit(1)
}

// Extract and format the information
if let info = nowPlayingInfo,
   let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String,
   let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
   let playbackRate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double,
   playbackRate == 1.0 {
    print("\(artist) - \(title)")
}