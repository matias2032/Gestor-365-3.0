//lib/services/push_notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import 'sessao_service.dart'; // 🔥 NOVO

class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._();
  PushNotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  bool _inicializado = false;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  Future<void> inicializar() async {
    if (_inicializado) return;

    try {
      // 1️⃣ Solicitar permissões
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Permissões FCM concedidas');
      } else {
        print('⚠️ Permissões FCM negadas');
        return;
      }

      // 2️⃣ Obter token FCM
      _fcmToken = await _fcm.getToken();
      print('🔑 FCM Token: $_fcmToken');

      // 3️⃣ Inscrever no tópico "estoque_ruptura"
      await _fcm.subscribeToTopic('estoque_ruptura');
      print('📢 Inscrito no tópico: estoque_ruptura');

      // 4️⃣ Configurar notificações locais
      await _configurarNotificacoesLocais();

      // 5️⃣ Configurar handlers de mensagens
      _configurarHandlers();

      _inicializado = true;
      print('✅ PushNotificationService inicializado');
      
    } catch (e) {
      print('❌ Erro ao inicializar FCM: $e');
    }
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
    // 🔥 FOREGROUND: App aberto
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📬 Mensagem recebida (foreground): ${message.notification?.title}');
      _mostrarNotificacaoLocal(message);
    });

    // 🔥 BACKGROUND: App minimizado
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📬 Notificação aberta (background): ${message.data}');
      _navegarParaProdutos(message);
    });

    // 🔥 TERMINATED: App fechado (configurado no main.dart)
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

  // 🔥 MODIFICADO: Validar sessão antes de navegar (notificação local clicada)
  Future<void> _onNotificationTap(NotificationResponse response) async {
    print('🔔 Notificação local clicada: ${response.payload}');
    
    // 🔥 VALIDAÇÃO CRÍTICA: Verificar se sessão é válida
    final sessaoValida = await SessaoService.instance.validarSessao();
    
    if (!sessaoValida) {
      print('⚠️ Sessão inválida - redirecionando para login');
      _navegarParaLogin();
      return;
    }
    
    // Se sessão válida, processar navegação
    if (response.payload != null) {
      final idProduto = int.tryParse(response.payload!);
      
      MyApp.navigatorKey.currentState?.pushReplacementNamed(
        '/gerenciar_produtos',
        arguments: {'id_produto': idProduto},
      );
    }
  }

  // 🔥 MODIFICADO: Validar sessão antes de navegar (notificação FCM clicada)
  Future<void> _navegarParaProdutos(RemoteMessage message) async {
    print('📦 Processando navegação: ${message.data}');
    
    // 🔥 VALIDAÇÃO CRÍTICA: Verificar se sessão é válida
    final sessaoValida = await SessaoService.instance.validarSessao();
    
    if (!sessaoValida) {
      print('⚠️ Sessão inválida - redirecionando para login');
      _navegarParaLogin();
      return;
    }
    
    // Se sessão válida, processar navegação
    final idProduto = message.data['id_produto'];
    
    if (idProduto != null) {
      MyApp.navigatorKey.currentState?.pushReplacementNamed(
        '/gerenciar_produtos',
        arguments: {'id_produto': int.tryParse(idProduto)},
      );
    } else {
      // Se não tiver id_produto específico, apenas ir para gerenciar produtos
      MyApp.navigatorKey.currentState?.pushReplacementNamed('/gerenciar_produtos');
    }
  }

  // 🔥 NOVO: Método para redirecionar para login
  void _navegarParaLogin() {
    // Usar addPostFrameCallback para garantir que a navegação ocorra após o frame atual
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = MyApp.navigatorKey.currentContext;
      if (context != null) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/',
          (route) => false,
        );
      }
    });
  }

  // 🔥 NOVO: Método público para processar notificação quando app é aberto do zero (terminated)
  // Este método deve ser chamado do main.dart após verificar getInitialMessage()
  Future<void> processarNotificacaoInicial(RemoteMessage message) async {
    print('📬 Processando notificação inicial (app terminated): ${message.data}');
    
    // Dar tempo para o app inicializar completamente
    await Future.delayed(const Duration(milliseconds: 500));
    
    // 🔥 VALIDAÇÃO CRÍTICA: Verificar se sessão é válida
    final sessaoValida = await SessaoService.instance.validarSessao();
    
    if (!sessaoValida) {
      print('⚠️ Sessão inválida - usuário precisa fazer login primeiro');
      // Não navegar - deixar o splash/main redirecionar para login
      return;
    }
    
    // Se sessão válida, processar navegação
    await _navegarParaProdutos(message);
  }

  Future<void> desinscreverTopico(String topico) async {
    await _fcm.unsubscribeFromTopic(topico);
    print('❌ Desinscrito do tópico: $topico');
  }

  void dispose() {
    // Cleanup se necessário
  }
}