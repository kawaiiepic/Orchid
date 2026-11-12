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
      }
      apply()
      result(nil)
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
  }

  private func loadPreview(for cover: Cover, completion: @escaping (UIImage?) -> Void) {
    DispatchQueue.main.async {
      if let image = self.previewImages[cover.id] {
        completion(image)
        return
      }
      URLSession.shared.dataTask(with: cover.preview) { data, _, error in
        let image = error == nil ? data.flatMap(UIImage.init(data:)) : nil
        DispatchQueue.main.async {
          if let image { self.previewImages[cover.id] = image }
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
      task.resume()
    }
  }

  private func finishVideo(key: String, localURL: URL?) {
    if let localURL, FileManager.default.fileExists(atPath: localURL.path) {
      localAssets[key] = localURL
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
