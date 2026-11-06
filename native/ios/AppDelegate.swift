import Flutter
import UIKit
import AVFoundation
import UserNotifications
import CoreImage.CIFilterBuiltins
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil && FirebaseApp.app() == nil { FirebaseApp.configure() }
    TomiMobileBridge.shared.observePrivacy()
    return super.application(application, didFinishLaunchingWithOptions: options)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    TomiMobileBridge.shared.install(engineBridge.applicationRegistrar.messenger())
  }
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if TomiMobileBridge.shared.open(url) { return true }
    return super.application(app, open: url, options: options)
  }
}

// Authentication, call consent and microphone publication stay in Dart controllers.
@MainActor
final class TomiMobileBridge {
  static let shared = TomiMobileBridge()
  private var channel: FlutterMethodChannel?
  private var audioLease: String?
  private var privacyCover: UIView?
  private var observers: [NSObjectProtocol] = []
  private var privacyEnabled = UserDefaults.standard.bool(forKey: "tomi.screenPrivacy")
  private var presenter: UIViewController? {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    var value = windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let next = value?.presentedViewController { value = next }
    return value
  }
  static func validLink(_ value: String) -> Bool {
    value.count <= 100 && (value.range(of: "^tomi://(profile|room)/[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$", options: .regularExpression) != nil || value.range(of: "^tomi://game/[a-fA-F0-9]{8}$", options: .regularExpression) != nil)
  }
  func open(_ url: URL) -> Bool {
    guard Self.validLink(url.absoluteString) else { return false }
    UserDefaults.standard.set(url.absoluteString, forKey: "tomi.pendingLink")
    channel?.invokeMethod("action", arguments: ["type": "deepLink"])
    return true
  }
  func install(_ messenger: FlutterBinaryMessenger) {
    let value = FlutterMethodChannel(name: "tomi/mobile", binaryMessenger: messenger)
    channel = value
    value.setMethodCallHandler { [weak self] call, result in DispatchQueue.main.async { self?.handle(call, result) } }
  }
  func observePrivacy() {
    guard observers.isEmpty else { return }
    for name in [UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification, UIScreen.capturedDidChangeNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.updatePrivacy(inactive: name == UIApplication.willResignActiveNotification) } })
    }
    DispatchQueue.main.async { self.updatePrivacy() }
  }
  private func updatePrivacy(inactive: Bool = false) {
    let hide = privacyEnabled && (inactive || UIScreen.main.isCaptured || UIApplication.shared.applicationState != .active)
    guard hide else { privacyCover?.removeFromSuperview(); privacyCover = nil; return }
    guard privacyCover == nil, let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else { return }
    let cover = UILabel(frame: window.bounds)
    cover.backgroundColor = UIColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1)
    cover.textColor = .white; cover.textAlignment = .center; cover.numberOfLines = 0
    cover.text = "TOMI\nالمحتوى مخفي أثناء مشاركة الشاشة"
    cover.isUserInteractionEnabled = true; cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover); privacyCover = cover
  }
  private func qr(_ value: String) throws -> UIImage {
    guard Self.validLink(value) else { throw NSError(domain: "TOMI", code: 1) }
    let filter = CIFilter.qrCodeGenerator(); filter.message = Data(value.utf8); filter.correctionLevel = "M"
    guard let raw = filter.outputImage else { throw NSError(domain: "TOMI", code: 2) }
    let scale = floor(512 / raw.extent.width), output = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard let image = CIContext().createCGImage(output, from: output.extent) else { throw NSError(domain: "TOMI", code: 3) }
    return UIImage(cgImage: image)
  }
  private func share(_ items: [Any], _ result: @escaping FlutterResult) {
    guard let view = presenter else { result(FlutterError(code: "NOT_VISIBLE", message: "افتح التطبيق للمشاركة.", details: nil)); return }
    let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
    if let popover = sheet.popoverPresentationController { popover.sourceView = view.view; popover.sourceRect = CGRect(x: view.view.bounds.midX, y: view.view.bounds.midY, width: 1, height: 1); popover.permittedArrowDirections = [] }
    view.present(sheet, animated: true); result(nil)
  }
  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:], id = args["id"] as? String
    do {
      switch call.method {
      case "prepareVoiceAudio":
        let recording = args["recording"] as? Bool == true
        if audioLease != nil { if recording { result(FlutterError(code: "AUDIO_BUSY", message: "أنه المكالمة أو غادر الغرفة قبل التسجيل.", details: nil)) } else { result(false) }; return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(recording ? .playAndRecord : .playback, mode: .default, options: recording ? [.allowBluetooth] : [])
        try session.setActive(true); result(true)
      case "startAudio":
        guard UIApplication.shared.applicationState == .active, let value = id, audioLease == nil || audioLease == value else { result(false); return }
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
        try AVAudioSession.sharedInstance().setActive(true); audioLease = value; result(true)
      case "renewAudio":
        if audioLease == id && id != nil { result(nil) } else { result(FlutterError(code: "AUDIO_STOPPED", message: "توقفت جلسة الصوت.", details: nil)) }
      case "stopAudio":
        if id == audioLease { audioLease = nil; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }; result(nil)
      case "bind":
        let next = args["accountId"] as? String, old = UserDefaults.standard.string(forKey: "tomi.account")
        if old != next { audioLease = nil; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        UserDefaults.standard.set(next, forKey: "tomi.account"); result(nil)
      case "clearCall", "presentNotification": result(nil) // Firebase owns native alert presentation.
      case "takeAction", "takeNotification": result(nil)
      case "takeDeepLink":
        let value = UserDefaults.standard.string(forKey: "tomi.pendingLink"); UserDefaults.standard.removeObject(forKey: "tomi.pendingLink"); result(value)
      case "screenPrivacy":
        privacyEnabled = args["enabled"] as? Bool == true; UserDefaults.standard.set(privacyEnabled, forKey: "tomi.screenPrivacy"); updatePrivacy(); result(nil)
      case "notificationSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }; result(nil)
      case "deviceCheck":
        UNUserNotificationCenter.current().getNotificationSettings { settings in DispatchQueue.main.async {
          result(["microphone": AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, "camera": AVCaptureDevice.authorizationStatus(for: .video) == .authorized, "notifications": settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional])
        } }
      case "shareText":
        guard let text = args["text"] as? String, text.count <= 10000 else { result(FlutterError(code: "INVALID_SHARE", message: "محتوى غير صحيح.", details: nil)); return }; share([text], result)
      case "qrCode", "shareQr":
        guard let url = args["url"] as? String else { result(FlutterError(code: "INVALID_SHARE", message: "رابط غير صحيح.", details: nil)); return }
        let image = try qr(url)
        if call.method == "shareQr" { share([image, url], result) } else { result(FlutterStandardTypedData(bytes: image.pngData()!)) }
      default: result(FlutterMethodNotImplemented)
      }
    } catch { result(FlutterError(code: "MOBILE_UNAVAILABLE", message: "تعذّر تجهيز خدمة الهاتف.", details: nil)) }
  }
}
