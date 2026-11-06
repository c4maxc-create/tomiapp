import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts { _ = TomiMobileBridge.shared.open(context.url) }
  }
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let rest = URLContexts.filter { !TomiMobileBridge.shared.open($0.url) }
    if !rest.isEmpty { super.scene(scene, openURLContexts: Set(rest)) }
  }
}
