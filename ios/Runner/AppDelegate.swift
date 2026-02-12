import Flutter
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // 🔥 NOVO: Configurar Firebase
    FirebaseApp.configure()
    
    // 🔥 NOVO: Configurar notificações
    UNUserNotificationCenter.current().delegate = self
    
    // 🔥 NOVO: Limpar badge ao abrir app
    application.applicationIconBadgeNumber = 0
    
    // 🔥 NOVO: Registrar para notificações remotas
    application.registerForRemoteNotifications()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // 🔥 NOVO: Suprimir notificações quando app está em foreground (estilo WhatsApp)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Não mostrar alerta visual quando app está ativo
    // Apenas processar dados silenciosamente
    completionHandler([])
  }
  
  // 🔥 NOVO: Handler quando usuário toca na notificação
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    // Limpar badge
    UIApplication.shared.applicationIconBadgeNumber = 0
    
    completionHandler()
  }
  
  // 🔥 NOVO: Registrar token APNs no Firebase
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
  }
  
  // 🔥 NOVO: Limpar notificações quando app volta para foreground
  override func applicationDidBecomeActive(_ application: UIApplication) {
    application.applicationIconBadgeNumber = 0
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
  }
}