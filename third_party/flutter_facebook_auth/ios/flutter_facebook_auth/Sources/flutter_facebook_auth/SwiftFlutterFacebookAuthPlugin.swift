import Flutter
import UIKit

import FBSDKCoreKit


@objc(FlutterFacebookAuthPlugin)
public class SwiftFlutterFacebookAuthPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
    lazy var facebookAuth = FacebookAuth()
    private var initialized = false
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "app.meedu/flutter_facebook_auth", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterFacebookAuthPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
        registrar.addSceneDelegate(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let appId = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String, !appId.isEmpty else {
            result(FlutterError(code: "FACEBOOK_CONFIG", message: "Facebook client configuration is not ready", details: nil))
            return
        }
        if !initialized { ApplicationDelegate.initialize(); initialized = true }
        self.facebookAuth.handle(call, result: result)
    }



    /// START ALLOW HANDLE NATIVE FACEBOOK APP
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable : Any] = [:]) -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") != nil else { return true }
        var options = [UIApplication.LaunchOptionsKey: Any]()
        for (k, value) in launchOptions {
            let key = k as! UIApplication.LaunchOptionsKey
            options[key] = value
        }
        ApplicationDelegate.shared.application(application,didFinishLaunchingWithOptions: options)
        return true
    }

    public func application( _ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:] ) -> Bool {
        let processed = ApplicationDelegate.shared.application(
            app, open: url,
            sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String,
            annotation: options[UIApplication.OpenURLOptionsKey.annotation])
        return processed;
    }

    // Scene lifecycle equivalent of `application(_:open:options:)`. iOS 13+
    // routes URL openings (including the native Facebook app callback via the
    // fb<APP_ID>:// scheme) here when UIApplicationSceneManifest is enabled.
    public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
        return URLContexts.contains { context in
            guard context.url.scheme?.hasPrefix("fb") == true else { return false }

            return ApplicationDelegate.shared.application(
                UIApplication.shared,
                open: context.url,
                sourceApplication: context.options.sourceApplication,
                annotation: context.options.annotation
            )
        }
    }
    /// END ALLOW HANDLE NATIVE FACEBOOK APP
}
