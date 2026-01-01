// ==========================================
// 1. PROVIDER DE ESTADO - lib/services/estoque_alerta_service.dart
// ==========================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'base_de_dados.dart';
import 'notificacao_estoque_service.dart';

enum NivelAlerta { nenhum, laranja, vermelho }

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
  DateTime? _ultimoAlerta;
  Timer? _timerVerificacao;
  bool _alertaVisivel = false;

  List<ProdutoAlerta> get alertas => _alertas;
  bool get temAlertas => _alertas.isNotEmpty;
  int get totalAlertas => _alertas.length;
  bool get alertaVisivel => _alertaVisivel;
  
  NivelAlerta get nivelMaisCritico {
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
    
    // Verificar a cada 5 minutos
    _timerVerificacao = Timer.periodic(
      const Duration(minutes: 5),
      (_) => verificarEstoque(),
    );
  }

  // Em lib/services/estoque_alerta_service.dart
// SUBSTITUIR o método verificarEstoque():

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

    _alertas = resultado.map((row) {
      final qtd = row['quantidade_estoque'] as int;
      return ProdutoAlerta(
        id: row['id_produto'] as int,
        nome: row['nome_produto'] as String,
        quantidade: qtd,
        nivel: qtd < 10 ? NivelAlerta.vermelho : NivelAlerta.laranja,
      );
    }).toList();

    // Mostrar alerta se passou 1 hora desde o último
    if (_alertas.isNotEmpty) {
      final agora = DateTime.now();
      if (_ultimoAlerta == null || 
          agora.difference(_ultimoAlerta!).inHours >= 1) {
        _alertaVisivel = true;
        
        // 🔥 ADICIONAR: Disparar notificação externa
        await NotificacaoEstoqueService.instance.mostrarAlertaEstoque(_alertas);
      }
    } else {
      _alertaVisivel = false;
    }

    notifyListeners();
  } catch (e) {
    print('❌ Erro ao verificar estoque: $e');
  }
}

  Future<void> marcarComoLido() async {
    _alertaVisivel = false;
    _ultimoAlerta = DateTime.now();
    await _salvarUltimoAlerta();
    notifyListeners();
  }

  Future<void> _carregarUltimoAlerta() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString('ultimo_alerta_estoque');
    if (timestamp != null) {
      _ultimoAlerta = DateTime.parse(timestamp);
    }
  }

  Future<void> _salvarUltimoAlerta() async {
    final prefs = await SharedPreferences.getInstance();
    if (_ultimoAlerta != null) {
      await prefs.setString('ultimo_alerta_estoque', _ultimoAlerta!.toIso8601String());
    }
  }

  void dispose() {
    _timerVerificacao?.cancel();
    super.dispose();
  }
}