// lib/services/notificacao_estoque_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'estoque_alerta_service.dart';
import '../main.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'dart:io' show Platform;

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
      await _solicitarPermissoes();
    } else {
      print('❌ Falha ao inicializar notificações');
    }
  }

  Future<void> _solicitarPermissoes() async {
    final androidImplementation = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidImplementation != null) {
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

    if (response.payload == 'validade_alerta') {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    MyApp.navigatorKey.currentState?.pushReplacementNamed('/gerenciar_produtos');
  });
}
  }

  // 🔥 CORRIGIDO: Resumo Diário (18h) - SEM som customizado
  Future<void> mostrarResumoDiario(List<ProdutoAlerta> alertas) async {
    if (alertas.isEmpty || !_inicializado) return;

    final laranjas = alertas.where((a) => a.nivel == NivelAlerta.laranja).length;
    final vermelhos = alertas.where((a) => a.nivel == NivelAlerta.vermelho).length;
    final rupturas = alertas.where((a) => a.nivel == NivelAlerta.ruptura).length;

    final titulo = '📊 Relatório de Estoque';
    String corpo = '';
    
    if (rupturas > 0) {
      corpo += '$rupturas produto(s) em RUPTURA! ';
    }
    if (vermelhos > 0) {
      corpo += '$vermelhos em alerta vermelho. ';
    }
    if (laranjas > 0) {
      corpo += '$laranjas em alerta laranja. ';
    }
    corpo += 'Toque para revisar antes do pico.';

    // 🔥 CORREÇÃO: Remover som customizado, usar som padrão do sistema
    final androidDetails = AndroidNotificationDetails(
      'resumo_diario',
      'Resumo Diário de Estoque',
      channelDescription: 'Relatório diário de estoque às 18h',
      importance: Importance.high,
      priority: Priority.high,
      color: const Color(0xFF2196F3),
      enableVibration: true,
      playSound: true, // Usa som padrão do sistema
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(corpo),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notifications.show(
        1, // ID diferente do alerta de ruptura
        titulo,
        corpo,
        details,
        payload: 'estoque_alerta',
      );
      print('✅ Resumo diário enviado');
    } catch (e) {
      print('❌ Erro ao enviar resumo diário: $e');
    }
  }

  // 🔥 CORRIGIDO: Alerta de Ruptura - SEM som customizado
  Future<void> mostrarAlertaRuptura(ProdutoAlerta produto) async {
    if (!_inicializado) return;

    final titulo = 'RUPTURA DE ESTOQUE!';
    final corpo = 'O produto "${produto.nome}" está com ESTOQUE ZERADO! '
                  'Reponha imediatamente para evitar perda de vendas.';

    // 🔥 CORREÇÃO: Remover som customizado inexistente
    final androidDetails = AndroidNotificationDetails(
      'alerta_ruptura',
      'Alerta de Ruptura',
      channelDescription: 'Notificações de ruptura de estoque (estoque zerado)',
      importance: Importance.max,
      priority: Priority.max,
      color: const Color(0xFF8B0000),
      enableVibration: true,
      playSound: true, // Usa som padrão do sistema
      // 🔥 REMOVIDO: sound: const RawResourceAndroidNotificationSound('notification'),
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(corpo),
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'repor',
          'Repor Agora',
          showsUserInterface: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notifications.show(
        2, // ID único para rupturas
        titulo,
        corpo,
        details,
        payload: 'estoque_alerta',
      );
      print('✅ Alerta de ruptura enviado: ${produto.nome}');
    } catch (e) {
      print('❌ Erro ao enviar alerta de ruptura: $e');
    }
  }

  Future<void> cancelarTodas() async {
    await _notifications.cancelAll();
  }

  // lib/services/notificacao_estoque_service.dart
// ADICIONAR ESTES MÉTODOS À CLASSE NotificacaoEstoqueService

// 🔥 NOVO: Método para cancelar notificação específica
Future<void> cancelarNotificacao(int id) async {
  try {
    await _notifications.cancel(id);
    print('✅ Notificação $id cancelada');
  } catch (e) {
    print('❌ Erro ao cancelar notificação $id: $e');
  }
}

Future<void> mostrarNotificacaoSimples({
  required int id,
  required String titulo,
  required String corpo,
  String payload = 'validade_alerta',
}) async {
  if (!_inicializado) return;

  final androidDetails = AndroidNotificationDetails(
    'alerta_validade',
    'Alerta de Validade',
    channelDescription: 'Notificações de produtos com prazo de validade a expirar',
    importance: Importance.high,
    priority: Priority.high,
    color: const Color(0xFFFF6600),
    enableVibration: true,
    playSound: true,
    icon: '@mipmap/ic_launcher',
    styleInformation: BigTextStyleInformation(corpo),
  );

  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  try {
    await _notifications.show(
      id,
      titulo,
      corpo,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
    print('✅ Notificação de validade enviada: $titulo');
  } catch (e) {
    print('❌ Erro ao enviar notificação de validade: $e');
  }
}

// 🔥 NOVO: Método para agendar notificação
// 🔥 CORRIGIDO: Método para agendar notificação
Future<void> agendarNotificacao({
  required int id,
  required String titulo,
  required String corpo,
  required dynamic quando,
}) async {
  if (!_inicializado) {
    print('⚠️ Notificações não inicializadas');
    return;
  }

  try {
    // Inicializar timezone se ainda não foi
    tz.initializeTimeZones();
    
    // Converter para TZDateTime
    final tz.TZDateTime scheduledDate = quando is tz.TZDateTime
        ? quando
        : tz.TZDateTime.from(quando as DateTime, tz.local);
    
    print('📅 Agendando notificação #$id para: $scheduledDate');
    
    const androidDetails = AndroidNotificationDetails(
      'resumo_diario',
      'Resumo Diário de Estoque',
      channelDescription: 'Relatório diário de estoque às 18h',
      importance: Importance.max,
      priority: Priority.max,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // 🔥 CORREÇÃO: Remover parâmetros obsoletos
    await _notifications.zonedSchedule(
      id,
      titulo,
      corpo,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // Repetir diariamente
    );

    print('✅ Notificação #$id agendada com sucesso');
  } catch (e) {
    print('❌ Erro ao agendar notificação: $e');
    rethrow;
  }
}
}