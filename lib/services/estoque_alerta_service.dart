// lib/services/estoque_alerta_service.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'base_de_dados.dart';
import 'notificacao_estoque_service.dart';
// 🔥 ADICIONAR IMPORTS NECESSÁRIOS
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum NivelAlerta { nenhum, laranja, vermelho, ruptura }

class ProdutoAlerta {
  final int id;
  final String nome;
  final int quantidade;
  final NivelAlerta nivel;

  ProdutoAlerta({
    required this.id,
    required this.nome,
    required this.quantidade,
    required this.nivel,
  });
}

class EstoqueAlertaService extends ChangeNotifier {
  static final EstoqueAlertaService instance = EstoqueAlertaService._();
  EstoqueAlertaService._();

  final DatabaseService _db = DatabaseService.instance;
  
  List<ProdutoAlerta> _alertas = [];
  DateTime? _ultimoAlertaPopup;
  DateTime? _ultimoResumo;
  Timer? _timerVerificacao;
  Timer? _timerResumoDiario;
  bool _alertaVisivel = false;

  List<ProdutoAlerta> get alertas => _alertas;
  bool get temAlertas => _alertas.isNotEmpty;
  int get totalAlertas => _alertas.length;
  bool get alertaVisivel => _alertaVisivel;
  
  List<ProdutoAlerta> get alertasCriticos => _alertas
      .where((a) => a.nivel == NivelAlerta.vermelho || a.nivel == NivelAlerta.ruptura)
      .toList();
  
  bool get temAlertasCriticos => alertasCriticos.isNotEmpty;
  
  NivelAlerta get nivelMaisCritico {
    if (_alertas.any((a) => a.nivel == NivelAlerta.ruptura)) {
      return NivelAlerta.ruptura;
    }
    if (_alertas.any((a) => a.nivel == NivelAlerta.vermelho)) {
      return NivelAlerta.vermelho;
    }
    if (_alertas.any((a) => a.nivel == NivelAlerta.laranja)) {
      return NivelAlerta.laranja;
    }
    return NivelAlerta.nenhum;
  }

  Color get corAlerta {
    switch (nivelMaisCritico) {
      case NivelAlerta.ruptura:
        return const Color(0xFF8B0000);
      case NivelAlerta.vermelho:
        return Colors.red;
      case NivelAlerta.laranja:
        return Colors.orange;
      case NivelAlerta.nenhum:
        return Colors.green;
    }
  }

  Future<void> inicializar() async {
    await _carregarUltimoAlerta();
    await verificarEstoque();
    
    // 🔥 CORRIGIDO: Acesso correto ao plugin de notificações
    await NotificacaoEstoqueService.instance.cancelarNotificacao(999);
    
    _timerVerificacao = Timer.periodic(
      const Duration(minutes: 5),
      (_) => verificarEstoque(),
    );

    _agendarResumoDiario();
  }

  void _agendarResumoDiario() {
    _timerResumoDiario?.cancel();
    
    final agora = DateTime.now();
    var proximoResumo = DateTime(agora.year, agora.month, agora.day, 18, 0);
    
    if (agora.isAfter(proximoResumo)) {
      proximoResumo = proximoResumo.add(const Duration(days: 1));
    }
    
    final duracao = proximoResumo.difference(agora);
    
    _agendarNotificacaoNativa(proximoResumo);
    
    _timerResumoDiario = Timer(duracao, () {
      _enviarResumoDiario();
      _agendarResumoDiario();
    });
    
    print('📅 Resumo diário agendado para: ${proximoResumo.toString()}');
  }

  // 🔥 CORRIGIDO: Sintaxe e tipos corretos
  Future<void> _agendarNotificacaoNativa(DateTime quando) async {
  try {
    // 🔥 CORREÇÃO: Garantir que a hora esteja no fuso local
    final now = DateTime.now();
    final scheduledDate = DateTime(
      quando.year,
      quando.month,
      quando.day,
      18, // Fixo às 18h
      0,  // 0 minutos
      0,  // 0 segundos
    );
    
    // Se já passou das 18h hoje, agendar para amanhã
    final finalDate = scheduledDate.isBefore(now)
        ? scheduledDate.add(const Duration(days: 1))
        : scheduledDate;
    
    final tzDate = tz.TZDateTime.from(finalDate, tz.local);
    
    print('📅 Agendando notificação das 18h para: $tzDate');
    
    await NotificacaoEstoqueService.instance.agendarNotificacao(
      id: 999,
      titulo: '📊 Relatório de Estoque',
      corpo: 'Hora de revisar o estoque antes do pico de vendas. Toque para ver detalhes.',
      quando: tzDate,
    );
  } catch (e) {
    print('❌ Erro ao agendar notificação: $e');
  }
}
  Future<void> _enviarResumoDiario() async {
    await verificarEstoque();
    
    if (_alertas.isNotEmpty) {
      await NotificacaoEstoqueService.instance.mostrarResumoDiario(_alertas);
      _ultimoResumo = DateTime.now();
      await _salvarUltimoResumo();
    }
  }

  Future<void> verificarEstoque() async {
    try {
      final db = await _db.database;
      
      final resultado = await db.rawQuery('''
        SELECT id_produto, nome_produto, quantidade_estoque
        FROM produto
        WHERE ativo = 1 
          AND quantidade_estoque IS NOT NULL
          AND quantidade_estoque < 20
        ORDER BY quantidade_estoque ASC
      ''');

      final alertasAntigos = Map.fromEntries(
        _alertas.map((a) => MapEntry(a.id, a.nivel))
      );

      _alertas = resultado.map((row) {
        final qtd = row['quantidade_estoque'] as int;
        NivelAlerta nivel;
        if (qtd == 0) {
          nivel = NivelAlerta.ruptura;
        } else if (qtd < 10) {
          nivel = NivelAlerta.vermelho;
        } else {
          nivel = NivelAlerta.laranja;
        }
        
        return ProdutoAlerta(
          id: row['id_produto'] as int,
          nome: row['nome_produto'] as String,
          quantidade: qtd,
          nivel: nivel,
        );
      }).toList();

      if (temAlertasCriticos) {
        final agora = DateTime.now();
        
        final passaram2Horas = _ultimoAlertaPopup == null || 
            agora.difference(_ultimoAlertaPopup!).inHours >= 2;
        
        final novoCritico = _alertas.any((alerta) {
          final nivelAnterior = alertasAntigos[alerta.id];
          return (alerta.nivel == NivelAlerta.vermelho || alerta.nivel == NivelAlerta.ruptura) &&
                 (nivelAnterior == null || nivelAnterior == NivelAlerta.laranja);
        });
        
        if (passaram2Horas || novoCritico) {
          _alertaVisivel = true;
        }
      } else {
        _alertaVisivel = false;
      }

      final rupturas = _alertas.where((a) => a.nivel == NivelAlerta.ruptura).toList();
      if (rupturas.isNotEmpty) {
        for (final ruptura in rupturas) {
          final nivelAnterior = alertasAntigos[ruptura.id];
          if (nivelAnterior != NivelAlerta.ruptura) {
            await NotificacaoEstoqueService.instance.mostrarAlertaRuptura(ruptura);
          }
        }
      }

      notifyListeners();
    } catch (e) {
      print('❌ Erro ao verificar estoque: $e');
    }
  }

  Future<void> marcarComoLido() async {
    _alertaVisivel = false;
    _ultimoAlertaPopup = DateTime.now();
    await _salvarUltimoAlerta();
    notifyListeners();
  }

  Future<void> _carregarUltimoAlerta() async {
    final prefs = await SharedPreferences.getInstance();
    final timestampPopup = prefs.getString('ultimo_alerta_popup');
    if (timestampPopup != null) {
      _ultimoAlertaPopup = DateTime.parse(timestampPopup);
    }
    
    final timestampResumo = prefs.getString('ultimo_resumo_diario');
    if (timestampResumo != null) {
      _ultimoResumo = DateTime.parse(timestampResumo);
    }
  }

  Future<void> _salvarUltimoAlerta() async {
    final prefs = await SharedPreferences.getInstance();
    if (_ultimoAlertaPopup != null) {
      await prefs.setString('ultimo_alerta_popup', _ultimoAlertaPopup!.toIso8601String());
    }
  }

  Future<void> _salvarUltimoResumo() async {
    final prefs = await SharedPreferences.getInstance();
    if (_ultimoResumo != null) {
      await prefs.setString('ultimo_resumo_diario', _ultimoResumo!.toIso8601String());
    }
  }

  @override
  void dispose() {
    _timerVerificacao?.cancel();
    _timerResumoDiario?.cancel();
    super.dispose();
  }
}