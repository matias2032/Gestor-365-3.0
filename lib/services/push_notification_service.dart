import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import 'sessao_service.dart';

class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._();
  PushNotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  bool _inicializado = false;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  // 🔥 NOVO: Inicializar com timeout
  Future<void> inicializar() async {
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
    final settings = await _fcm.requestPermission(
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

    _fcmToken = await _fcm.getToken();
    print('🔑 FCM Token: $_fcmToken');

    await _fcm.subscribeToTopic('estoque_ruptura');
    print('📢 Inscrito no tópico: estoque_ruptura');

    await _configurarNotificacoesLocais();
    _configurarHandlers();

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

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }

  void _configurarHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📬 Mensagem recebida (foreground): ${message.notification?.title}');
      _mostrarNotificacaoLocal(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📬 Notificação aberta (background): ${message.data}');
      _navegarParaProdutos(message);
    });
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

    await _localNotifications.show(
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
    await _fcm.unsubscribeFromTopic(topico);
    print('❌ Desinscrito do tópico: $topico');
  }

  void dispose() {}
}