import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'estoque_alerta_service.dart';
import '../main.dart';

class NotificacaoEstoqueService {
  static final NotificacaoEstoqueService instance = NotificacaoEstoqueService._();
  NotificacaoEstoqueService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _inicializado = false;

  Future<void> inicializar() async {
    if (_inicializado) return;

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

    final resultado = await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTap,
    );

    if (resultado == true) {
      print('✅ Notificações inicializadas com sucesso');
      _inicializado = true;
      
      // Solicitar permissões explicitamente no Android 13+
      await _solicitarPermissoes();
    } else {
      print('❌ Falha ao inicializar notificações');
    }
  }

  Future<void> _solicitarPermissoes() async {
    // CORREÇÃO: Adicionado o "<" antes de AndroidFlutterLocalNotificationsPlugin
    final androidImplementation = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidImplementation != null) {
      // Nota: Em versões mais recentes do plugin, o método pode ser requestNotificationsPermission()
      // ou requestPermission(). Verifique a versão do seu package se este sublinhar.
      final permissaoConcedida = await androidImplementation.requestNotificationsPermission();
      print('📲 Permissão de notificações: ${permissaoConcedida == true ? "CONCEDIDA" : "NEGADA"}');
    }
  }

  @pragma('vm:entry-point')
  static void _onNotificationTap(NotificationResponse response) {
    print('🔔 Notificação clicada: ${response.payload}');
    
    if (response.payload == 'estoque_alerta') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MyApp.navigatorKey.currentState?.pushReplacementNamed('/gerenciar_produtos');
      });
    }
  }

  Future<void> mostrarAlertaEstoque(List<ProdutoAlerta> alertas) async {
    if (alertas.isEmpty || !_inicializado) {
      print('⚠️ Sem alertas ou notificações não inicializadas');
      return;
    }

    final temCritico = alertas.any((a) => a.nivel == NivelAlerta.vermelho);
    final titulo = temCritico ? '🔴 Estoque Crítico!' : '🟠 Alerta de Estoque';
    
    final produtoMaisCritico = alertas.first;
    final totalAlertas = alertas.length;
    
    String corpo;
    if (totalAlertas == 1) {
      corpo = 'O produto "${produtoMaisCritico.nome}" está com apenas '
          '${produtoMaisCritico.quantidade} unidades em estoque.';
    } else {
      corpo = '$totalAlertas produtos com estoque baixo. '
          '"${produtoMaisCritico.nome}" (${produtoMaisCritico.quantidade} un.) '
          'é o mais crítico. Toque para repor.';
    }

    final androidDetails = AndroidNotificationDetails(
      'estoque_alertas',
      'Alertas de Estoque',
      channelDescription: 'Notificações sobre estoque baixo',
      importance: Importance.high,
      priority: Priority.high,
      color: const Color(0xFFFF5722),
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'repor',
          'Repor Estoque',
          showsUserInterface: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    // CORREÇÃO: Removido 'const' pois androidDetails é uma variável 'final' calculada em runtime
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notifications.show(
        0, 
        titulo,
        corpo,
        details,
        payload: 'estoque_alerta',
      );
      print('✅ Notificação enviada: $titulo');
    } catch (e) {
      print('❌ Erro ao enviar notificação: $e');
    }
  }

  Future<void> cancelarTodas() async {
    await _notifications.cancelAll();
  }
}