import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import 'sessao_service.dart';
import 'estoque_alerta_service.dart';
import 'package:flutter/foundation.dart'; 
class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._();
  PushNotificationService._();
FirebaseMessaging? _fcm;

FlutterLocalNotificationsPlugin? _localNotifications;
  
  bool _inicializado = false;
  String? _fcmToken;
  bool _appEmForeground = true;

  String? get fcmToken => _fcmToken;

  // 🔥 NOVO: Inicializar com timeout
  Future<void> inicializar() async {
     if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
    print('⏭️ FCM não suportado nesta plataforma');
    return;
  }
    if (_inicializado) return;

    try {
      await Future.any([
        _inicializarFCM(),
        Future.delayed(const Duration(seconds: 8), () {
          throw TimeoutException('FCM timeout após 8s');
        }),
      ]);
    } catch (e) {
      print('⚠️ FCM não inicializado: $e');
      // Continuar sem FCM
    }
  }

  Future<void> _inicializarFCM() async {
    _fcm = FirebaseMessaging.instance;

    final settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      print('⚠️ Permissões FCM negadas');
      return;
    }

    print('✅ Permissões FCM concedidas');

    _fcmToken = await _fcm!.getToken();
    print('🔑 FCM Token: $_fcmToken');

    await _fcm!.subscribeToTopic('estoque_ruptura');
    print('📢 Inscrito no tópico: estoque_ruptura');


_localNotifications = FlutterLocalNotificationsPlugin();
    await _configurarNotificacoesLocais();
    _configurarHandlers();
    _monitorarEstadoApp();

    _inicializado = true;
    print('✅ PushNotificationService inicializado');
  }

  Future<void> _configurarNotificacoesLocais() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

await _localNotifications!.initialize(   // ← adicionar !
  settings,
  onDidReceiveNotificationResponse: _onNotificationTap,
);
  }

  // 🔥 NOVO: Monitorar estado do app (foreground/background)
  void _monitorarEstadoApp() {
    WidgetsBinding.instance.addObserver(_AppLifecycleListener(
      onResumed: () {
        _appEmForeground = true;
        _limparNotificacoesAoAbrirApp();
      },
      onPaused: () {
        _appEmForeground = false;
      },
    ));
  }

  void _configurarHandlers() {
    // 🔥 MODIFICADO: Só mostrar notificação se app estiver em background
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📬 Mensagem recebida (foreground): ${message.notification?.title}');
      
      if (!_appEmForeground) {
        // App está em background, mas processo ativo - mostrar notificação
        _mostrarNotificacaoLocal(message);
      } else {
        // App está ativo - apenas atualizar dados silenciosamente
        print('✋ App ativo - notificação suprimida (estilo WhatsApp)');
        _atualizarEstoqueSilenciosamente();
      }
    });

    // Handler para quando usuário clica na notificação (app em background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📬 Notificação aberta (background): ${message.data}');
      _navegarParaProdutos(message);
    });
  }

  // 🔥 NOVO: Atualizar estoque sem mostrar notificação
  Future<void> _atualizarEstoqueSilenciosamente() async {
    try {
      await EstoqueAlertaService.instance.verificarEstoque();
      print('🔄 Estoque atualizado silenciosamente');
    } catch (e) {
      print('⚠️ Erro ao atualizar estoque: $e');
    }
  }

  // 🔥 NOVO: Limpar todas as notificações ao abrir o app
  Future<void> _limparNotificacoesAoAbrirApp() async {
    try {
      // Cancelar todas as notificações locais pendentes
   await _localNotifications?.cancelAll();
      
      // Limpar badge no iOS
      await _fcm!.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      
      print('✅ Notificações limpas ao abrir app');
    } catch (e) {
      print('⚠️ Erro ao limpar notificações: $e');
    }
  }

  Future<void> _mostrarNotificacaoLocal(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'alerta_ruptura',
      'Alertas de Ruptura de Estoque',
      channelDescription: 'Notificações críticas de estoque zerado',
      importance: Importance.max,
      priority: Priority.max,
      color: Color(0xFF8B0000),
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

await _localNotifications?.show(         // ← usar ?.
  notification.hashCode,
  notification.title,
  notification.body,
  details,
  payload: message.data['id_produto']?.toString(),
);
  }

  Future<void> _onNotificationTap(NotificationResponse response) async {
    print('🔔 Notificação local clicada: ${response.payload}');
    
    final sessaoValida = await SessaoService.instance.validarSessao();
    
    if (!sessaoValida) {
      print('⚠️ Sessão inválida - redirecionando para login');
      _navegarParaLogin();
      return;
    }
    
    if (response.payload != null) {
      final idProduto = int.tryParse(response.payload!);
      
      MyApp.navigatorKey.currentState?.pushReplacementNamed(
        '/gerenciar_produtos',
        arguments: {'id_produto': idProduto},
      );
    }
  }

  Future<void> _navegarParaProdutos(RemoteMessage message) async {
    print('📦 Processando navegação: ${message.data}');
    
    final sessaoValida = await SessaoService.instance.validarSessao();
    
    if (!sessaoValida) {
      print('⚠️ Sessão inválida - redirecionando para login');
      _navegarParaLogin();
      return;
    }
    
    final idProduto = message.data['id_produto'];
    
    if (idProduto != null) {
      MyApp.navigatorKey.currentState?.pushReplacementNamed(
        '/gerenciar_produtos',
        arguments: {'id_produto': int.tryParse(idProduto)},
      );
    } else {
      MyApp.navigatorKey.currentState?.pushReplacementNamed('/gerenciar_produtos');
    }
  }

  void _navegarParaLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = MyApp.navigatorKey.currentContext;
      if (context != null) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    });
  }

  Future<void> processarNotificacaoInicial(RemoteMessage message) async {
    print('📬 Processando notificação inicial (app terminated): ${message.data}');
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    final sessaoValida = await SessaoService.instance.validarSessao();
    
    if (!sessaoValida) {
      print('⚠️ Sessão inválida - usuário precisa fazer login primeiro');
      return;
    }
    
    await _navegarParaProdutos(message);
  }

  Future<void> desinscreverTopico(String topico) async {
    await _fcm!.unsubscribeFromTopic(topico);
    print('❌ Desinscrito do tópico: $topico');
  }

  void dispose() {}
}

// 🔥 NOVO: Listener de ciclo de vida do app
class _AppLifecycleListener extends WidgetsBindingObserver {
  final VoidCallback onResumed;
  final VoidCallback onPaused;

  _AppLifecycleListener({
    required this.onResumed,
    required this.onPaused,
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onResumed();
        break;
      case AppLifecycleState.paused:
        onPaused();
        break;
      default:
        break;
    }
  }
}