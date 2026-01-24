// lib/services/servico_movimento_estoque.dart
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; //
import '../models/movimento_estoque.dart';
import 'base_de_dados.dart';
import 'supabase_sync_service.dart';

class ServicoMovimentoEstoque {
  static final ServicoMovimentoEstoque instance = ServicoMovimentoEstoque._init();
  ServicoMovimentoEstoque._init();

  final DatabaseService _dbService = DatabaseService.instance;

  // Stream controller para notificações em tempo real
  final _movimentoStreamController = StreamController<MovimentoEstoque>.broadcast();
  Stream<MovimentoEstoque> get movimentoStream => _movimentoStreamController.stream;

  /// Registra um movimento manual de estoque
  Future<int> registrarMovimentoManual({
    required int idProduto,
    required int idUsuario,
    required int quantidadeAnterior,
    required int quantidadeNova,
    String? motivo,
  }) async {
    final db = await _dbService.database;

    final diferenca = quantidadeNova - quantidadeAnterior;

    if (diferenca == 0) {
      throw Exception('Não houve alteração na quantidade');
    }

    final tipoMovimento = diferenca > 0 ? TipoMovimento.acrescimo : TipoMovimento.reducao;
    final quantidadeMovimento = diferenca.abs();

    // Buscar device_id
    final deviceId = await _getDeviceId();

    final movimento = MovimentoEstoque(
      idProduto: idProduto,
      idUsuario: idUsuario,
      tipoMovimento: tipoMovimento,
      quantidade: quantidadeMovimento,
      quantidadeAnterior: quantidadeAnterior,
      quantidadeNova: quantidadeNova,
      motivo: motivo,
      dataMovimento: DateTime.now().toUtc().toIso8601String(),
    );

    // Preparar mapa e inserir device_id
    final movimentoMap = movimento.toMap();
    movimentoMap['device_id'] = deviceId;

    // Inserir no SQLite
    final id = await db.insert('movimento_estoque', movimentoMap);

    // Sincronizar com Supabase
    await _sincronizarMovimentoComSupabase(id, movimentoMap);

    // Notificar listeners
    final movimentoCompleto = await _buscarMovimentoPorId(id);
    if (movimentoCompleto != null) {
      _movimentoStreamController.add(movimentoCompleto);
    }

    return id;
  }

  /// Atualiza estoque manualmente E registra o movimento (Transacional)
  Future<void> atualizarEstoqueManual({
    required int idProduto,
    required int novaQuantidade,
    required int idUsuario,
    String? motivo,
  }) async {
    final db = await _dbService.database;
    
    // Variáveis para guardar dados e usar após a transação
    int? idMovimentoGerado;
    Map<String, dynamic>? dadosParaSync;

    // 🔥 OTIMIZAÇÃO: Buscamos o device_id ANTES da transação para não travar o banco
    final deviceId = await _getDeviceId();

    await db.transaction((txn) async {
      // 1. Buscar quantidade atual
      final produtoMaps = await txn.query(
        'produto',
        columns: ['quantidade_estoque', 'nome_produto'],
        where: 'id_produto = ?',
        whereArgs: [idProduto],
      );

      if (produtoMaps.isEmpty) {
        throw Exception('Produto não encontrado');
      }

      final quantidadeAnterior = produtoMaps.first['quantidade_estoque'] as int? ?? 0;

      if (novaQuantidade < 0) {
        throw Exception('A quantidade não pode ser negativa');
      }

      // 2. Atualizar estoque
      await txn.update(
        'produto',
        {'quantidade_estoque': novaQuantidade},
        where: 'id_produto = ?',
        whereArgs: [idProduto],
      );

      // 3. Registrar movimento se houver diferença
      final diferenca = novaQuantidade - quantidadeAnterior;

      if (diferenca != 0) {
        final tipoMovimento = diferenca > 0 ? TipoMovimento.acrescimo : TipoMovimento.reducao;

        final movimento = MovimentoEstoque(
          idProduto: idProduto,
          idUsuario: idUsuario,
          tipoMovimento: tipoMovimento,
          quantidade: diferenca.abs(),
          quantidadeAnterior: quantidadeAnterior,
          quantidadeNova: novaQuantidade,
          motivo: motivo,
          dataMovimento: DateTime.now().toUtc().toIso8601String(),
          nomeProduto: produtoMaps.first['nome_produto'] as String,
        );

        final movimentoMap = movimento.toMap();
        movimentoMap['device_id'] = deviceId; // Usamos o deviceId obtido fora da txn

        // Inserir e capturar o ID
        final id = await txn.insert('movimento_estoque', movimentoMap);
        
        // Guardar dados para sync posterior (fora da transaction)
        idMovimentoGerado = id;
        dadosParaSync = movimentoMap;

        // Buscar usuário para notificação local
        final usuarioMaps = await txn.query(
          'usuario',
          columns: ['nome', 'apelido'],
          where: 'id_usuario = ?',
          whereArgs: [idUsuario],
        );

        if (usuarioMaps.isNotEmpty) {
          final nomeUsuario = '${usuarioMaps.first['nome']} ${usuarioMaps.first['apelido']}';
          final movimentoCompleto = movimento.copyWith(
            id: id,
            nomeUsuario: nomeUsuario,
          );
          _movimentoStreamController.add(movimentoCompleto);
        }
      }
    });

    // 4. Executar sincronização fora da transação
    if (idMovimentoGerado != null && dadosParaSync != null) {
      await _sincronizarMovimentoComSupabase(idMovimentoGerado!, dadosParaSync!);
    }

    // Notificar mudança geral no estoque
    _dbService.notificarMudancaEstoque();
  }

  // --- MÉTODOS AUXILIARES ---

  /// Sincroniza um movimento específico com o Supabase
  Future<void> _sincronizarMovimentoComSupabase(int idLocal, Map<String, dynamic> movimentoData) async {
    try {
      final syncService = SupabaseSyncService.instance;

      if (!syncService.isOnline) {
        print('📴 Offline - movimento será sincronizado depois pelo worker');
        return;
      }

      // 🔥 CORREÇÃO PRINCIPAL AQUI:
      // Trocamos 'syncService.supabase' por 'Supabase.instance.client'
      await Supabase.instance.client.from('movimento_estoque').insert({ //
        'id_movimento': idLocal,
        'id_produto': movimentoData['id_produto'],
        'id_usuario': movimentoData['id_usuario'],
        'tipo_movimento': movimentoData['tipo_movimento'],
        'quantidade': movimentoData['quantidade'],
        'quantidade_anterior': movimentoData['quantidade_anterior'],
        'quantidade_nova': movimentoData['quantidade_nova'],
        'motivo': movimentoData['motivo'],
        'device_id': movimentoData['device_id'],
        'data_movimento': movimentoData['data_movimento'],
      });

      print('✅ Movimento $idLocal sincronizado com Supabase');
    } catch (e) {
      print('⚠️ Erro ao sincronizar movimento com Supabase: $e');
    }
  }

  /// Obtém o device_id do SharedPreferences
  Future<String?> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('device_id');
    } catch (e) {
      print('⚠️ Erro ao obter device_id: $e');
      return null;
    }
  }

  /// Busca movimento por ID com informações completas
  Future<MovimentoEstoque?> _buscarMovimentoPorId(int id) async {
    final db = await _dbService.database;

    final maps = await db.rawQuery('''
      SELECT 
        m.*,
        p.nome_produto,
        u.nome || ' ' || u.apelido as nome_usuario
      FROM movimento_estoque m
      INNER JOIN produto p ON m.id_produto = p.id_produto
      INNER JOIN usuario u ON m.id_usuario = u.id_usuario
      WHERE m.id_movimento = ?
    ''', [id]);

    if (maps.isNotEmpty) {
      return MovimentoEstoque.fromMap(maps.first);
    }
    return null;
  }

  /// Busca histórico de movimentos com filtros
  Future<List<MovimentoEstoque>> buscarHistorico({
    int? idProduto,
    int? idUsuario,
    DateTime? dataInicio,
    DateTime? dataFim,
    TipoMovimento? tipoMovimento,
    int limit = 100,
  }) async {
    final db = await _dbService.database;

    String where = '1=1';
    List<dynamic> whereArgs = [];

    if (idProduto != null) {
      where += ' AND m.id_produto = ?';
      whereArgs.add(idProduto);
    }

    if (idUsuario != null) {
      where += ' AND m.id_usuario = ?';
      whereArgs.add(idUsuario);
    }

    if (dataInicio != null) {
      where += ' AND m.data_movimento >= ?';
      whereArgs.add(dataInicio.toIso8601String());
    }

    if (dataFim != null) {
      where += ' AND m.data_movimento <= ?';
      whereArgs.add(dataFim.toIso8601String());
    }

    if (tipoMovimento != null) {
      where += ' AND m.tipo_movimento = ?';
      whereArgs.add(tipoMovimento.valor); 
    }

    final maps = await db.rawQuery('''
      SELECT 
        m.*,
        p.nome_produto,
        u.nome || ' ' || u.apelido as nome_usuario
      FROM movimento_estoque m
      INNER JOIN produto p ON m.id_produto = p.id_produto
      INNER JOIN usuario u ON m.id_usuario = u.id_usuario
      WHERE $where
      ORDER BY m.data_movimento DESC
      LIMIT ?
    ''', [...whereArgs, limit]);

    return maps.map((map) => MovimentoEstoque.fromMap(map)).toList();
  }

  /// Busca movimentos de um produto específico
  Future<List<MovimentoEstoque>> buscarMovimentosProduto(int idProduto) async {
    return buscarHistorico(idProduto: idProduto);
  }

  /// Estatísticas de movimentos
  Future<Map<String, dynamic>> obterEstatisticas({
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    final db = await _dbService.database;

    String where = '1=1';
    List<dynamic> whereArgs = [];

    if (dataInicio != null) {
      where += ' AND data_movimento >= ?';
      whereArgs.add(dataInicio.toIso8601String());
    }

    if (dataFim != null) {
      where += ' AND data_movimento <= ?';
      whereArgs.add(dataFim.toIso8601String());
    }

    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_movimentos,
        SUM(CASE WHEN tipo_movimento = 'ACRESCIMO' THEN quantidade ELSE 0 END) as total_acrescimos,
        SUM(CASE WHEN tipo_movimento = 'REDUCAO' THEN quantidade ELSE 0 END) as total_reducoes,
        COUNT(DISTINCT id_produto) as produtos_afetados,
        COUNT(DISTINCT id_usuario) as usuarios_registraram
      FROM movimento_estoque
      WHERE $where
    ''', whereArgs);

    return result.first;
  }

  void dispose() {
    _movimentoStreamController.close();
  }
}

extension MovimentoEstoqueCopyWith on MovimentoEstoque {
  MovimentoEstoque copyWith({
    int? id,
    int? idProduto,
    int? idUsuario,
    TipoMovimento? tipoMovimento,
    int? quantidade,
    int? quantidadeAnterior,
    int? quantidadeNova,
    String? motivo,
    String? dataMovimento,
    String? nomeProduto,
    String? nomeUsuario,
  }) {
    return MovimentoEstoque(
      id: id ?? this.id,
      idProduto: idProduto ?? this.idProduto,
      idUsuario: idUsuario ?? this.idUsuario,
      tipoMovimento: tipoMovimento ?? this.tipoMovimento,
      quantidade: quantidade ?? this.quantidade,
      quantidadeAnterior: quantidadeAnterior ?? this.quantidadeAnterior,
      quantidadeNova: quantidadeNova ?? this.quantidadeNova,
      motivo: motivo ?? this.motivo,
      dataMovimento: dataMovimento ?? this.dataMovimento,
      nomeProduto: nomeProduto ?? this.nomeProduto,
      nomeUsuario: nomeUsuario ?? this.nomeUsuario,
    );
  }
}