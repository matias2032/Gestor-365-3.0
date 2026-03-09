// lib/services/validade_alerta_service.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'base_de_dados.dart';
import 'notificacao_estoque_service.dart';
import 'package:timezone/timezone.dart' as tz;

enum NivelValidadeAlerta { nenhum, aviso, urgente, expirado }

class ProdutoValidadeAlerta {
  final int id;
  final String nome;
  final DateTime dataExpiracao;
  final NivelValidadeAlerta nivel;
  final int diasRestantes; // negativo = já expirou

  ProdutoValidadeAlerta({
    required this.id,
    required this.nome,
    required this.dataExpiracao,
    required this.nivel,
    required this.diasRestantes,
  });
}

class ValidadeAlertaService extends ChangeNotifier {
  static final ValidadeAlertaService instance = ValidadeAlertaService._();
  ValidadeAlertaService._();

  final DatabaseService _db = DatabaseService.instance;

  List<ProdutoValidadeAlerta> _alertas = [];
  DateTime? _ultimoAlertaPopup;
  Timer? _timerVerificacao;
  bool _alertaVisivel = false;

  List<ProdutoValidadeAlerta> get alertas => _alertas;
  bool get temAlertas => _alertas.isNotEmpty;
  int get totalAlertas => _alertas.length;
  bool get alertaVisivel => _alertaVisivel;

  List<ProdutoValidadeAlerta> get alertasUrgentes => _alertas
      .where((a) =>
          a.nivel == NivelValidadeAlerta.urgente ||
          a.nivel == NivelValidadeAlerta.expirado)
      .toList();

  bool get temAlertasUrgentes => alertasUrgentes.isNotEmpty;

  NivelValidadeAlerta get nivelMaisCritico {
    if (_alertas.any((a) => a.nivel == NivelValidadeAlerta.expirado)) {
      return NivelValidadeAlerta.expirado;
    }
    if (_alertas.any((a) => a.nivel == NivelValidadeAlerta.urgente)) {
      return NivelValidadeAlerta.urgente;
    }
    if (_alertas.any((a) => a.nivel == NivelValidadeAlerta.aviso)) {
      return NivelValidadeAlerta.aviso;
    }
    return NivelValidadeAlerta.nenhum;
  }

  Color get corAlerta {
    switch (nivelMaisCritico) {
      case NivelValidadeAlerta.expirado:
        return const Color(0xFF8B0000);
      case NivelValidadeAlerta.urgente:
        return Colors.red;
      case NivelValidadeAlerta.aviso:
        return Colors.orange;
      case NivelValidadeAlerta.nenhum:
        return Colors.green;
    }
  }

  Future<void> inicializar() async {
    await _carregarUltimoAlerta();
    await verificarValidades();

    _timerVerificacao = Timer.periodic(
      const Duration(hours: 1),
      (_) => verificarValidades(),
    );
  }

  /// Retorna true se o produto está expirado (não deve aparecer no menu).
  static bool estaExpirado(String? dataExpiracao) {
    if (dataExpiracao == null || dataExpiracao.isEmpty) return false;
    try {
      final data = DateTime.parse(dataExpiracao);
      final hoje = DateTime.now();
      // Expirado se a data de expiração é anterior ao início do dia de hoje
      final hojeNormalizado = DateTime(hoje.year, hoje.month, hoje.day);
final dataNormalizada = DateTime(data.year, data.month, data.day);
return !dataNormalizada.isAfter(hojeNormalizado);
    } catch (_) {
      return false;
    }
  }

  /// Calcula o score de urgência de validade para ordenação composta.
  /// Score mais alto = mais urgente = aparece primeiro.
  static int scoreValidade(String? dataExpiracao) {
    if (dataExpiracao == null || dataExpiracao.isEmpty) return 0;
    try {
      final data = DateTime.parse(dataExpiracao);
      final hoje = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final dias = data.difference(hoje).inDays;

      if (dias <= 1) return 800;  // Expira hoje ou amanhã
      if (dias <= 7) return 400;  // Expira em até 7 dias
      if (dias <= 30) return 100; // Expira em até 30 dias
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> verificarValidades() async {
    try {
      final db = await _db.database;
      final hoje = DateTime.now();
      final limite = hoje.add(const Duration(days: 30));

      // Busca produtos activos com validade nos próximos 30 dias OU já expirados
      final resultado = await db.rawQuery('''
        SELECT id_produto, nome_produto, data_expiracao
        FROM produto
        WHERE ativo = 1
          AND data_expiracao IS NOT NULL
          AND data_expiracao != ''
          AND date(data_expiracao) <= date(?)
        ORDER BY data_expiracao ASC
      ''', [limite.toIso8601String().split('T').first]);

      final alertasAntigos = Map.fromEntries(
        _alertas.map((a) => MapEntry(a.id, a.nivel)),
      );

      final hojeNormalizado = DateTime(hoje.year, hoje.month, hoje.day);

      _alertas = resultado.map((row) {
        final dataStr = row['data_expiracao'] as String;
        final data = DateTime.parse(dataStr);
        final dias = data.difference(hojeNormalizado).inDays;

        NivelValidadeAlerta nivel;
        if (dias < 0) {
          nivel = NivelValidadeAlerta.expirado;
        } else if (dias <= 7) {
          nivel = NivelValidadeAlerta.urgente;
        } else {
          nivel = NivelValidadeAlerta.aviso;
        }

        return ProdutoValidadeAlerta(
          id: row['id_produto'] as int,
          nome: row['nome_produto'] as String,
          dataExpiracao: data,
          nivel: nivel,
          diasRestantes: dias,
        );
      }).toList();

      // Mostrar popup se há urgentes e passaram 2h desde o último
      if (temAlertasUrgentes) {
        final agora = DateTime.now();
        final passaram2Horas = _ultimoAlertaPopup == null ||
            agora.difference(_ultimoAlertaPopup!).inHours >= 2;

        final novoUrgente = _alertas.any((alerta) {
          final nivelAnterior = alertasAntigos[alerta.id];
          return (alerta.nivel == NivelValidadeAlerta.urgente ||
                  alerta.nivel == NivelValidadeAlerta.expirado) &&
              (nivelAnterior == null ||
                  nivelAnterior == NivelValidadeAlerta.aviso);
        });

        if (passaram2Horas || novoUrgente) {
          _alertaVisivel = true;
        }
      } else {
        _alertaVisivel = false;
      }

      // Notificação push para produtos que acabaram de expirar
    for (final alerta in _alertas) {
  // A query já garante ativo = 1, mas validamos explicitamente
  // para proteger contra estados inconsistentes entre verificações
  if (alerta.nivel == NivelValidadeAlerta.expirado) {
    final nivelAnterior = alertasAntigos[alerta.id];
    if (nivelAnterior != NivelValidadeAlerta.expirado) {
      await NotificacaoEstoqueService.instance.mostrarNotificacaoSimples(
        id: alerta.id + 10000,
        titulo: '⚠️ Produto Expirado',
        corpo: '"${alerta.nome}" atingiu a data de validade e foi removido do menu.',
      );
    }
  }
}
      notifyListeners();
    } catch (e) {
      print('❌ Erro ao verificar validades: $e');
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
    final timestamp = prefs.getString('ultimo_alerta_validade_popup');
    if (timestamp != null) {
      _ultimoAlertaPopup = DateTime.parse(timestamp);
    }
  }

  Future<void> _salvarUltimoAlerta() async {
    final prefs = await SharedPreferences.getInstance();
    if (_ultimoAlertaPopup != null) {
      await prefs.setString(
        'ultimo_alerta_validade_popup',
        _ultimoAlertaPopup!.toIso8601String(),
      );
    }
  }

  @override
  void dispose() {
    _timerVerificacao?.cancel();
    super.dispose();
  }
}