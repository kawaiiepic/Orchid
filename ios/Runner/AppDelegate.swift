import Flutter
import UIKit
import AVKit
import AVFoundation
import MediaPlayer

/// Embeds Apple's real audio output route selector. UIKit presents nearby
/// AirPlay/Bluetooth routes directly, with no fake device discovery.
private final class OrchidRoutePicker: NSObject, FlutterPlatformView {
  private let picker: AVRoutePickerView

  init(frame: CGRect) {
    picker = AVRoutePickerView(frame: frame)
    picker.prioritizesVideoDevices = false
    picker.tintColor = UIColor(red: 0.88, green: 0.34, blue: 0.61, alpha: 1)
    picker.activeTintColor = UIColor(red: 0.88, green: 0.34, blue: 0.61, alpha: 1)
    super.init()
  }

  func view() -> UIView { picker }
}

private final class OrchidRoutePickerFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect,
              viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    OrchidRoutePicker(frame: frame)
  }
}


@available(iOS 26.0, *)
private final class OrchidLockScreenArtwork: NSObject, AVAssetDownloadDelegate {
  private struct Cover {
    let id: String
    let title: String
    let artist: String
    let hls: URL
    let preview: URL
  }
  private var cover: Cover?
  private var animatedArtwork: MPMediaItemAnimatedArtwork?
  private var previewImages: [String: UIImage] = [:]
  private var localAssets: [String: URL] = [:]
  private var pendingVideo: [String: [(URL?) -> Void]] = [:]
  private var taskKeys: [Int: String] = [:]
  private var downloadLocations: [Int: URL] = [:]
  private var lastError: String?
  private var previewReady = false

  private func log(_ message: String) {
    NSLog("[Orchid Animated Artwork] %@", message)
  }

  private lazy var downloads: AVAssetDownloadURLSession = {
    let configuration = URLSessionConfiguration.background(
      withIdentifier: "dev.blossomvale.orchid.animated-artwork"
    )
    configuration.isDiscretionary = false
    return AVAssetDownloadURLSession(
      configuration: configuration,
      assetDownloadDelegate: self,
      delegateQueue: OperationQueue.main
    )
  }()

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "set":
      guard let args = call.arguments as? [String: String],
            let id = args["id"], let title = args["title"],
            let artist = args["artist"],
            let video = URL(string: args["video"] ?? ""),
            video.scheme == "https", video.pathExtension.lowercased() == "m3u8",
            let preview = URL(string: args["preview"] ?? ""),
            preview.scheme == "https" else {
        result(FlutterError(code: "invalid_artwork", message: "Expected HTTPS HLS and preview URLs", details: nil))
        return
      }
      let next = Cover(id: id, title: title, artist: artist, hls: video, preview: preview)
      if cover?.id != next.id || cover?.hls != next.hls || cover?.preview != next.preview {
        cover = next
        animatedArtwork = nil
        previewReady = false
        lastError = nil
      }
      // Warm both assets while the song is playing. Apple may request them
      // immediately after the lock screen appears, so avoid starting the
      // network download inside its request callback.
      loadPreview(for: next) { [weak self] _ in
        guard let self, self.cover?.id == next.id,
              self.cover?.hls == next.hls else { return }
        self.apply()
      }
      loadVideo(for: next) { [weak self] localURL in
        guard let self, self.cover?.id == next.id,
              self.cover?.hls == next.hls else { return }
        if localURL != nil { self.apply() }
      }
      apply()
      result(nil)
    case "status":
      let key = cover?.hls.absoluteString
      result([
        "track": cover?.id ?? "",
        "supported": MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys.contains(MPNowPlayingInfoProperty1x1AnimatedArtwork),
        "previewReady": previewReady,
        "videoReady": key.flatMap { localAssets[$0] }.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
        "downloading": key.flatMap { pendingVideo[$0] } != nil,
        "lastError": lastError ?? "",
        "metadataAttached": MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoProperty1x1AnimatedArtwork] != nil
      ] as [String: Any])
    case "refresh":
      apply()
      result(nil)
    case "clear":
      cover = nil
      animatedArtwork = nil
      var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
      info.removeValue(forKey: MPNowPlayingInfoProperty1x1AnimatedArtwork)
      info.removeValue(forKey: MPNowPlayingInfoProperty3x4AnimatedArtwork)
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func apply() {
    guard let cover,
          MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys.contains(
            MPNowPlayingInfoProperty1x1AnimatedArtwork
          ) else { return }
    let center = MPNowPlayingInfoCenter.default()
    guard var info = center.nowPlayingInfo,
          (info[MPMediaItemPropertyTitle] as? String) == cover.title,
          (info[MPMediaItemPropertyArtist] as? String) == cover.artist else { return }
    // Publishing too early can cause iOS to settle on the static cover.
    let key = cover.hls.absoluteString
    guard previewImages[cover.id] != nil,
          let local = localAssets[key],
          FileManager.default.fileExists(atPath: local.path) else { return }
    if animatedArtwork == nil {
      animatedArtwork = MPMediaItemAnimatedArtwork(
        artworkID: cover.id,
        previewImageRequestHandler: { [weak self] _, completion in
          self?.loadPreview(for: cover, completion: completion)
        },
        videoAssetFileURLRequestHandler: { [weak self] _, completion in
          self?.loadVideo(for: cover, completion: completion)
        }
      )
    }
    info[MPNowPlayingInfoProperty1x1AnimatedArtwork] = animatedArtwork
    center.nowPlayingInfo = info
    log("Published ready 1x1 animated artwork to Now Playing")
  }

  private func loadPreview(for cover: Cover, completion: @escaping (UIImage?) -> Void) {
    DispatchQueue.main.async {
      if let image = self.previewImages[cover.id] {
        completion(image)
        return
      }
      URLSession.shared.dataTask(with: cover.preview) { data, _, error in
        let downloaded = error == nil ? data.flatMap(UIImage.init(data:)) : nil
        // A rectangular image can cause iOS to ignore 1x1 animated artwork.
        let image: UIImage?
        if let source = downloaded {
          let side = min(source.size.width, source.size.height)
          let format = UIGraphicsImageRendererFormat()
          format.scale = 1
          image = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format
          ).image { _ in
            source.draw(at: CGPoint(
              x: (side - source.size.width) / 2,
              y: (side - source.size.height) / 2
            ))
          }
        } else {
          image = nil
        }
        DispatchQueue.main.async {
          if let image {
            self.previewImages[cover.id] = image
            self.previewReady = true
            self.log("Square preview ready")
          } else {
            self.lastError = "Preview download or decoding failed"
            self.log(self.lastError!)
          }
          completion(image)
        }
      }.resume()
    }
  }

  private func loadVideo(for cover: Cover, completion: @escaping (URL?) -> Void) {
    DispatchQueue.main.async {
      let key = cover.hls.absoluteString
      if let local = self.localAssets[key],
         FileManager.default.fileExists(atPath: local.path) {
        self.log("Serving cached HLS animated artwork")
        completion(local)
        return
      }
      if let saved = UserDefaults.standard.string(forKey: "orchid.artwork." + key),
         let local = URL(string: saved),
         FileManager.default.fileExists(atPath: local.path) {
        self.localAssets[key] = local
        self.log("Restored cached HLS animated artwork from disk")
        completion(local)
        return
      }
      if self.pendingVideo[key] != nil {
        self.pendingVideo[key]?.append(completion)
        return
      }
      self.pendingVideo[key] = [completion]
      let asset = AVURLAsset(url: cover.hls)
      guard let task = self.downloads.makeAssetDownloadTask(
        asset: asset, assetTitle: cover.id, assetArtworkData: nil, options: nil
      ) else {
        self.finishVideo(key: key, localURL: nil)
        return
      }
      self.taskKeys[task.taskIdentifier] = key
      self.log("Starting HLS animated artwork download")
      task.resume()
    }
  }

  private func finishVideo(key: String, localURL: URL?) {
    if let localURL, FileManager.default.fileExists(atPath: localURL.path) {
      localAssets[key] = localURL
      UserDefaults.standard.set(localURL.absoluteString, forKey: "orchid.artwork." + key)
      log("HLS animated artwork download completed: \(localURL.lastPathComponent)")
    } else {
      log("No valid local HLS artwork asset found")
    }
    let callbacks = pendingVideo.removeValue(forKey: key) ?? []
    callbacks.forEach { $0(localAssets[key]) }
  }

  // The system owns downloaded HLS package paths. They must not be moved.
  func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                  willDownloadTo location: URL) {
    downloadLocations[assetDownloadTask.taskIdentifier] = location
  }

  func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                  didFinishDownloadingTo location: URL) {
    downloadLocations[assetDownloadTask.taskIdentifier] = location
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
                  didCompleteWithError error: Error?) {
    guard let key = taskKeys.removeValue(forKey: task.taskIdentifier) else { return }
    let local = error == nil ? downloadLocations[task.taskIdentifier] : nil
    if let error {
      lastError = "HLS download failed: \(error.localizedDescription)"
      log(lastError!)
    } else if local == nil {
      lastError = "HLS download completed without a local package URL"
      log(lastError!)
    }
    downloadLocations.removeValue(forKey: task.taskIdentifier)
    finishVideo(key: key, localURL: local)
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var lockScreenArtwork: AnyObject?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if #available(iOS 26.0, *),
       let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OrchidLockScreenArtwork") {
      let bridge = OrchidLockScreenArtwork()
      lockScreenArtwork = bridge
      let channel = FlutterMethodChannel(
        name: "dev.blossomvale.orchid/animated-now-playing",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak bridge] call, result in
        bridge?.handle(call, result: result)
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OrchidRoutePicker") {
      registrar.register(
        OrchidRoutePickerFactory(),
        withId: "orchid/airplay-route-picker"
      )
    }
  }
}
