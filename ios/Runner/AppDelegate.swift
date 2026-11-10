import Flutter
import UIKit
import AVKit

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

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OrchidRoutePicker") {
      registrar.register(
        OrchidRoutePickerFactory(),
        withId: "orchid/airplay-route-picker"
      )
    }
  }
}
