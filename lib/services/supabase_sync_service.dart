// lib/services/supabase_sync_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'base_de_dados.dart';
import '../models/produto.dart';
import '../models/categoria.dart';
import '../models/pedido.dart';
import '../models/usuario.dart';
import '../models/produto_imagem.dart';

// ==========================================
// ENUMS E CLASSES AUXILIARES
// ==========================================

enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  offline
}

class OfflineOperation {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  OfflineOperation({
    required this.type,
    required this.data,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };

  factory OfflineOperation.fromJson(Map<String, dynamic> json) {
    return OfflineOperation(
      type: json['type'],
      data: Map<String, dynamic>.from(json['data']),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

// ==========================================
// SERVIÇO PRINCIPAL
// ==========================================

class SupabaseSyncService {
  static final SupabaseSyncService instance = SupabaseSyncService._init();
  SupabaseSyncService._init();

  final SupabaseClient _supabase = Supabase.instance.client;
  final DatabaseService _localDb = DatabaseService.instance;

  // Stream Controllers
  final _statusStreamController = StreamController<SyncStatus>.broadcast();
  final _erroStreamController = StreamController<String>.broadcast();

  Stream<SyncStatus> get statusStream => _statusStreamController.stream;
  Stream<String> get erroStream => _erroStreamController.stream;

  // Estado
  bool _isSyncing = false;
  bool _isOnline = true;
  DateTime? _lastSyncTime;
  String? _deviceId;
  String? _estabelecimentoId; // 🔥 REMOVER SE NÃO USAR MULTI-TENANT
  List<OfflineOperation> _offlineQueue = [];

  // Canais Realtime
  RealtimeChannel? _produtosChannel;
  RealtimeChannel? _pedidosChannel;

  // ==========================================
  // INICIALIZAÇÃO
  // ==========================================

  Future<void> initialize({String? estabelecimentoId}) async {
    try {
      print('🔄 Inicializando Supabase Sync Service...');
      
      _estabelecimentoId = estabelecimentoId;
      _deviceId = await _getOrCreateDeviceId();
      await _loadOfflineQueue();
      await _loadLastSyncTime();
      _setupConnectivityListener();
      
      // 🔥 COMENTADO: Listeners Realtime causam problemas sem estabelecimento_id
      // _setupRealtimeListeners();

      // Sincronização inicial
      await syncAll();

      print('✅ Supabase Sync Service inicializado!');
    } catch (e) {
      print('❌ Erro ao inicializar: $e');
      _updateStatus(SyncStatus.error);
    }
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');

    if (deviceId == null) {
      deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', deviceId);
    }

    return deviceId;
  }

  Future<void> _loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString('last_sync_time');
    if (timeStr != null && timeStr.isNotEmpty) {
      _lastSyncTime = DateTime.parse(timeStr);
    }
  }

  // ==========================================
  // CONECTIVIDADE
  // ==========================================

  void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
      final wasOffline = !_isOnline;
      _isOnline = results.isNotEmpty && !results.contains(ConnectivityResult.none);

      if (_isOnline && wasOffline) {
        print('🌐 Conexão restaurada! Sincronizando...');
        await syncOfflineQueue();
        await syncAll();
      } else if (!_isOnline) {
        print('📵 Modo offline ativado');
        _updateStatus(SyncStatus.offline);
      }
    });
  }

  // ==========================================
  // SINCRONIZAÇÃO COMPLETA
  // ==========================================

  Future<void> syncAll() async {
    if (_isSyncing || !_isOnline) return;

    _isSyncing = true;
    _updateStatus(SyncStatus.syncing);

    try {
      print('🔄 Iniciando sincronização completa...');

      await Future.wait([
        _syncProdutos(),
        _syncCategorias(),
        _syncPedidos(),
      ]);

      _lastSyncTime = DateTime.now();
      await _saveLastSyncTime();

      _updateStatus(SyncStatus.success);
      print('✅ Sincronização completa concluída!');
    } catch (e) {
      print('❌ Erro na sincronização: $e');
      _updateStatus(SyncStatus.error);
      _emitError('Erro na sincronização: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ==========================================
  // SINCRONIZAÇÃO DE PRODUTOS
  // ==========================================

  Future<void> _syncProdutos() async {
    try {
      // 🔥 CORRIGIDO: Removido filtro por estabelecimento_id
      final response = await _supabase
          .from('produtos')
          .select('*')
          .order('updated_at', ascending: false);

      for (final produtoMap in response) {
        await _syncProdutoFromSupabase(produtoMap);
      }

      print('✅ ${response.length} produtos sincronizados');
    } catch (e) {
      print('❌ Erro ao sincronizar produtos: $e');
      rethrow;
    }
  }

  Future<void> _syncProdutoFromSupabase(Map<String, dynamic> data) async {
    try {
      // 🔥 CORRIGIDO: Mapeamento seguro com valores padrão
      final produto = Produto(
        id: data['id_produto'] as int?,
        nome: data['nome_produto'] as String? ?? 'Sem nome',
        descricao: data['descricao'] as String?,
        preco: (data['preco'] as num?)?.toDouble() ?? 0.0,
        precoPromocional: data['preco_promocional'] != null 
            ? (data['preco_promocional'] as num).toDouble() 
            : null,
        quantidadeEstoque: data['quantidade_estoque'] as int? ?? 0,
        ativo: (data['ativo'] as int?) ?? 1,
        dataCadastro: (data['data_cadastro'] as String?) ?? DateTime.now().toIso8601String(),
      );

      // Verificar se o produto já existe
      if (produto.id != null) {
        final existente = await _localDb.readProdutoWithDetailsById(produto.id!);

        if (existente == null) {
          await _localDb.createProduto(produto, [], []);
        } else {
          await _localDb.updateProduto(
            produto,
            existente.categoriasAssociadas?.map((c) => c.id!).toList() ?? [],
            existente.imagens ?? [],
          );
        }
      }
    } catch (e) {
      print('❌ Erro ao sincronizar produto ${data['id_produto']}: $e');
    }
  }

  // ==========================================
  // SINCRONIZAÇÃO DE CATEGORIAS
  // ==========================================

  Future<void> _syncCategorias() async {
    try {
      // 🔥 CORRIGIDO: Removido filtro por estabelecimento_id
      final response = await _supabase
          .from('categorias')
          .select('*')
          .order('nome_categoria');

      for (final catMap in response) {
        final categoria = Categoria(
          id: catMap['id_categoria'] as int?,
          nome: catMap['nome_categoria'] as String? ?? 'Sem nome',
          descricao: catMap['descricao'] as String?,
        );

        if (categoria.id != null) {
          final existente = await _localDb.readCategoriaWithProdutosById(categoria.id!);

          if (existente == null) {
            await _localDb.createCategoria(categoria, []);
          }
        }
      }

      print('✅ ${response.length} categorias sincronizadas');
    } catch (e) {
      print('❌ Erro ao sincronizar categorias: $e');
    }
  }

  // ==========================================
  // SINCRONIZAÇÃO DE PEDIDOS
  // ==========================================

  Future<void> _syncPedidos() async {
    try {
      final dataLimite = DateTime.now().subtract(const Duration(days: 30));

      // 🔥 CORRIGIDO: Removido filtro por estabelecimento_id
      final response = await _supabase
          .from('pedidos')
          .select('*')
          .gte('data_pedido', dataLimite.toIso8601String())
          .order('data_pedido', ascending: false);

      print('✅ ${response.length} pedidos sincronizados');
    } catch (e) {
      print('❌ Erro ao sincronizar pedidos: $e');
    }
  }

  // ==========================================
  // CRUD PRODUTOS (COM SYNC AUTOMÁTICO)
  // ==========================================

  Future<int> createProduto(
    Produto produto,
    List<int> idsCategorias,
    List<ProdutoImagem> imagens,
  ) async {
    // 1. Salvar localmente
    final idLocal = await _localDb.createProduto(produto, idsCategorias, imagens);

    // 2. Sincronizar com Supabase
    if (_isOnline) {
      try {
        // 🔥 CORRIGIDO: Removido estabelecimento_id
        await _supabase.from('produtos').insert({
          'id_produto': idLocal,
          'nome_produto': produto.nome,
          'descricao': produto.descricao,
          'preco': produto.preco,
          'preco_promocional': produto.precoPromocional,
          'quantidade_estoque': produto.quantidadeEstoque ?? 0,
          'ativo': produto.ativo,
          'data_cadastro': produto.dataCadastro,
          'device_id': _deviceId,
        });
        print('✅ Produto $idLocal sincronizado com Supabase');
      } catch (e) {
        print('⚠️ Erro ao sincronizar produto: $e');
        _addToOfflineQueue(OfflineOperation(
          type: 'create_produto',
          data: {
            'produto': produto.copyWith(id: idLocal).toMap(),
            'categorias': idsCategorias,
            'id_local': idLocal,
          },
          timestamp: DateTime.now(),
        ));
      }
    } else {
      _addToOfflineQueue(OfflineOperation(
        type: 'create_produto',
        data: {
          'produto': produto.toMap(),
          'categorias': idsCategorias,
          'id_local': idLocal,
        },
        timestamp: DateTime.now(),
      ));
    }

    return idLocal;
  }

  Future<int> updateProduto(
    Produto produto,
    List<int> idsCategorias,
    List<ProdutoImagem> imagens,
  ) async {
    // 1. Atualizar localmente
    final result = await _localDb.updateProduto(produto, idsCategorias, imagens);

    // 2. Sincronizar com Supabase
    if (_isOnline && produto.id != null) {
      try {
        // 🔥 CORRIGIDO: Removido estabelecimento_id
        await _supabase
            .from('produtos')
            .update({
              'nome_produto': produto.nome,
              'descricao': produto.descricao,
              'preco': produto.preco,
              'preco_promocional': produto.precoPromocional,
              'quantidade_estoque': produto.quantidadeEstoque,
              'ativo': produto.ativo,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id_produto', produto.id!);
        print('✅ Produto ${produto.id} atualizado no Supabase');
      } catch (e) {
        print('⚠️ Erro ao sincronizar atualização: $e');
        _addToOfflineQueue(OfflineOperation(
          type: 'update_produto',
          data: {'produto': produto.toMap(), 'categorias': idsCategorias},
          timestamp: DateTime.now(),
        ));
      }
    } else {
      _addToOfflineQueue(OfflineOperation(
        type: 'update_produto',
        data: {'produto': produto.toMap(), 'categorias': idsCategorias},
        timestamp: DateTime.now(),
      ));
    }

    return result;
  }

  Future<int> deleteProduto(int idProduto) async {
    // 1. Deletar localmente
    final result = await _localDb.deleteProduto(idProduto);

    // 2. Sincronizar com Supabase
    if (_isOnline) {
      try {
        // 🔥 CORRIGIDO: Removido estabelecimento_id
        await _supabase
            .from('produtos')
            .delete()
            .eq('id_produto', idProduto);
        print('✅ Produto $idProduto deletado do Supabase');
      } catch (e) {
        print('⚠️ Erro ao sincronizar exclusão: $e');
      }
    }

    return result;
  }

  // ==========================================
  // CRUD CATEGORIAS (COM SYNC)
  // ==========================================

  Future<int> createCategoria(Categoria categoria, List<int> idsProdutos) async {
    final idLocal = await _localDb.createCategoria(categoria, idsProdutos);

    if (_isOnline) {
      try {
        await _supabase.from('categorias').insert({
          'id_categoria': idLocal,
          'nome_categoria': categoria.nome,
          'descricao': categoria.descricao,
        });
      } catch (e) {
        print('⚠️ Erro ao sincronizar categoria: $e');
      }
    }

    return idLocal;
  }

  Future<int> updateCategoria(Categoria categoria, List<int> idsProdutos) async {
    final result = await _localDb.updateCategoria(categoria, idsProdutos);

    if (_isOnline && categoria.id != null) {
      try {
        await _supabase
            .from('categorias')
            .update({
              'nome_categoria': categoria.nome,
              'descricao': categoria.descricao,
            })
            .eq('id_categoria', categoria.id!);
      } catch (e) {
        print('⚠️ Erro ao sincronizar categoria: $e');
      }
    }

    return result;
  }

  Future<int> deleteCategoria(int idCategoria) async {
    final result = await _localDb.deleteCategoria(idCategoria);

    if (_isOnline) {
      try {
        await _supabase
            .from('categorias')
            .delete()
            .eq('id_categoria', idCategoria);
      } catch (e) {
        print('⚠️ Erro ao sincronizar exclusão: $e');
      }
    }

    return result;
  }

  // ==========================================
  // CRUD PEDIDOS (COM SYNC)
  // ==========================================

  Future<int> createPedido(Pedido pedido, List<ItemPedido> itens) async {
    // 1. Criar localmente
    final idPedido = await _localDb.createPedido(pedido, itens);

    // 2. Sincronizar com Supabase
    if (_isOnline) {
      try {
        await _supabase.from('pedidos').insert({
          'id_pedido': idPedido,
          'reference': pedido.reference,
          'id_usuario': pedido.idUsuario,
          'total': pedido.total,
          'status_pedido': pedido.statusPedido,
          'data_pedido': pedido.dataPedido,
          'idtipo_pagamento': pedido.idTipoPagamento,
          'device_id': _deviceId,
        });

        // Inserir itens
        for (final item in itens) {
          await _supabase.from('itens_pedido').insert({
            'id_pedido': idPedido,
            'id_produto': item.idProduto,
            'quantidade': item.quantidade,
            'preco_unitario': item.precoUnitario,
            'subtotal': item.subtotal,
          });
        }

        print('✅ Pedido $idPedido sincronizado');
      } catch (e) {
        print('⚠️ Erro ao sincronizar pedido: $e');
        _addToOfflineQueue(OfflineOperation(
          type: 'create_pedido',
          data: {
            'pedido': pedido.toMap(),
            'itens': itens.map((i) => i.toMap()).toList(),
            'id_pedido': idPedido,
          },
          timestamp: DateTime.now(),
        ));
      }
    } else {
      _addToOfflineQueue(OfflineOperation(
        type: 'create_pedido',
        data: {
          'pedido': pedido.toMap(),
          'itens': itens.map((i) => i.toMap()).toList(),
          'id_pedido': idPedido,
        },
        timestamp: DateTime.now(),
      ));
    }

    return idPedido;
  }

  Future<void> cancelarPedido(int idPedido, String motivo, int idUsuarioCancelou) async {
    await _localDb.cancelarPedido(idPedido, motivo, idUsuarioCancelou);

    if (_isOnline) {
      try {
        await _supabase
            .from('pedidos')
            .update({
              'status_pedido': 'cancelado',
              'data_finalizacao': DateTime.now().toIso8601String(),
            })
            .eq('id_pedido', idPedido);
      } catch (e) {
        print('⚠️ Erro ao sincronizar cancelamento: $e');
      }
    }
  }

  Future<void> finalizarPedido(
    int idPedido,
    int idTipoPagamento, {
    double? valorPago,
    double? troco,
  }) async {
    await _localDb.finalizarPedido(
      idPedido,
      idTipoPagamento,
      valorPago: valorPago,
      troco: troco,
    );

    if (_isOnline) {
      try {
        await _supabase
            .from('pedidos')
            .update({
              'status_pedido': 'finalizado',
              'idtipo_pagamento': idTipoPagamento,
              'valor_pago_manual': valorPago,
              'troco': troco,
              'data_finalizacao': DateTime.now().toIso8601String(),
            })
            .eq('id_pedido', idPedido);
      } catch (e) {
        print('⚠️ Erro ao sincronizar finalização: $e');
      }
    }
  }

  // ==========================================
  // MÉTODOS DE LEITURA (DELEGAR AO LOCAL DB)
  // ==========================================

  Future<List<Produto>> readAllProdutosWithAssoc() async {
    return await _localDb.readAllProdutosWithAssoc();
  }

  Future<Produto?> readProdutoWithDetailsById(int idProduto) async {
    return await _localDb.readProdutoWithDetailsById(idProduto);
  }

  Future<List<Categoria>> readAllCategoriasWithProdutos() async {
    return await _localDb.readAllCategoriasWithProdutos();
  }

  Future<List<Categoria>> readAllCategoriasSimples() async {
    return await _localDb.readAllCategoriasSimples();
  }

  Future<List<Pedido>> readPedidosPorFinalizar(int idUsuario) async {
    return await _localDb.readPedidosPorFinalizar(idUsuario);
  }

  Future<Pedido?> readPedidoComDetalhes(int idPedido) async {
    return await _localDb.readPedidoComDetalhes(idPedido);
  }

  Future<List<Map<String, dynamic>>> getVendasPorCategoria(String dataInicio) async {
    return await _localDb.getVendasPorCategoria(dataInicio);
  }

  Future<List<Map<String, dynamic>>> getVendasCronologicas(String dataInicio) async {
    return await _localDb.getVendasCronologicas(dataInicio);
  }

  Future<List<Map<String, dynamic>>> readTiposPagamento() async {
    return await _localDb.readTiposPagamento();
  }

  // ==========================================
  // FILA OFFLINE
  // ==========================================

  void _addToOfflineQueue(OfflineOperation operation) {
    _offlineQueue.add(operation);
    _saveOfflineQueue();
    print('📝 Operação adicionada à fila offline: ${operation.type}');
  }

  Future<void> _loadOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString('offline_queue');

      if (queueJson != null && queueJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(queueJson);
        _offlineQueue = decoded
            .map((item) => OfflineOperation.fromJson(item))
            .toList();
        print('📥 ${_offlineQueue.length} operações carregadas da fila offline');
      }
    } catch (e) {
      print('❌ Erro ao carregar fila offline: $e');
      _offlineQueue = [];
    }
  }

  Future<void> _saveOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_offlineQueue.map((op) => op.toJson()).toList());
      await prefs.setString('offline_queue', encoded);
    } catch (e) {
      print('❌ Erro ao salvar fila offline: $e');
    }
  }

  Future<void> syncOfflineQueue() async {
    if (_offlineQueue.isEmpty || !_isOnline) return;

    print('🔄 Sincronizando ${_offlineQueue.length} operações offline...');

    final operations = List<OfflineOperation>.from(_offlineQueue);
    _offlineQueue.clear();

    for (final operation in operations) {
      try {
        await _processOfflineOperation(operation);
        print('✅ Operação processada: ${operation.type}');
      } catch (e) {
        print('❌ Erro ao processar operação ${operation.type}: $e');
        _offlineQueue.add(operation);
      }
    }

    await _saveOfflineQueue();
    print('✅ Fila offline sincronizada! ${_offlineQueue.length} pendentes');
  }

  Future<void> _processOfflineOperation(OfflineOperation operation) async {
    switch (operation.type) {
      case 'create_produto':
        final produto = Produto.fromMap(operation.data['produto']);
        await _supabase.from('produtos').insert({
          'id_produto': operation.data['id_local'],
          'nome_produto': produto.nome,
          'preco': produto.preco,
          'quantidade_estoque': produto.quantidadeEstoque,
          'ativo': produto.ativo,
        });
        break;

      case 'update_produto':
        final produto = Produto.fromMap(operation.data['produto']);
        if (produto.id != null) {
          await _supabase
              .from('produtos')
              .update({
                'nome_produto': produto.nome,
                'preco': produto.preco,
                'quantidade_estoque': produto.quantidadeEstoque,
              })
              .eq('id_produto', produto.id!);
        }
        break;

      case 'create_pedido':
        final pedidoData = operation.data['pedido'];
        await _supabase.from('pedidos').insert({
          'id_pedido': operation.data['id_pedido'],
          'id_usuario': pedidoData['id_usuario'],
          'total': pedidoData['total'],
          'status_pedido': pedidoData['status_pedido'],
        });
        break;
    }
  }

  // ==========================================
  // UTILITÁRIOS
  // ==========================================

  void _updateStatus(SyncStatus status) {
    _statusStreamController.add(status);
  }

  void _emitError(String error) {
    _erroStreamController.add(error);
  }

  Future<void> _saveLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'last_sync_time',
      _lastSyncTime?.toIso8601String() ?? '',
    );
  }

  // Getters
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingOperations => _offlineQueue.length;
  String? get estabelecimentoId => _estabelecimentoId;

  // ==========================================
  // LIMPEZA
  // ==========================================

  void dispose() {
    _produtosChannel?.unsubscribe();
    _pedidosChannel?.unsubscribe();
    _statusStreamController.close();
    _erroStreamController.close();
  }

  // ==========================================
  // MÉTODOS DE USUÁRIO
  // ==========================================

  Future<Usuario> createUsuario(Usuario usuario) async {
    return await _localDb.createUsuario(usuario);
  }

  Future<Usuario?> readUsuario(int id) async {
    return await _localDb.readUsuario(id);
  }

  Future<Usuario?> readUsuarioByEmail(String email) async {
    return await _localDb.readUsuarioByEmail(email);
  }

  Future<Usuario?> readUsuarioByCredencial(String credencial) async {
    return await _localDb.readUsuarioByCredencial(credencial);
  }

  Future<int> updateUsuario(Usuario usuario) async {
    return await _localDb.updateUsuario(usuario);
  }

  Future<int> deleteUsuario(int id) async {
    return await _localDb.deleteUsuario(id);
  }

  Future<List<Usuario>> readAllUsuarios() async {
    return await _localDb.readAllUsuarios();
  }

  Future<int> toggleAtivoUsuario(int id, bool isActive) async {
    return await _localDb.toggleAtivoUsuario(id, isActive);
  }

  // ==========================================
  // MÉTODOS DE PRODUTOS (COMPLEMENTARES)
  // ==========================================

  Future<List<Produto>> readAllProdutosSimples() async {
    return await _localDb.readAllProdutosSimples();
  }

  Future<Categoria?> readCategoriaWithProdutosById(int idCategoria) async {
    return await _localDb.readCategoriaWithProdutosById(idCategoria);
  }

  // ==========================================
  // MÉTODOS DE PEDIDO (COMPLEMENTARES)
  // ==========================================

  Future<void> updateQuantidadeItem(int idItemPedido, int novaQuantidade) async {
    await _localDb.updateQuantidadeItem(idItemPedido, novaQuantidade);

    if (_isOnline) {
      try {
        final db = await _localDb.database;
        final itemMaps = await db.query(
          'item_pedido',
          where: 'id_item_pedido = ?',
          whereArgs: [idItemPedido],
        );

        if (itemMaps.isNotEmpty) {
          final idPedido = itemMaps.first['id_pedido'] as int;
          final totalResult = await db.rawQuery(
            'SELECT SUM(subtotal) as total FROM item_pedido WHERE id_pedido = ?',
            [idPedido],
          );
          final total = (totalResult.first['total'] as num?)?.toDouble() ?? 0.0;

          // 🔥 CORRIGIDO: Removido estabelecimento_id
          await _supabase
              .from('pedidos')
              .update({'total': total})
              .eq('id_pedido', idPedido);
        }
      } catch (e) {
        print('⚠️ Erro ao sincronizar atualização de item: $e');
      }
    }
  }

  Future<void> deleteItemPedido(int idItemPedido) async {
    await _localDb.deleteItemPedido(idItemPedido);

    // Sincronizar exclusão com Supabase
    if (_isOnline) {
      try {
        // 🔥 CORRIGIDO: Removido estabelecimento_id
        await _supabase
            .from('itens_pedido')
            .delete()
            .eq('id_item_pedido', idItemPedido);
      } catch (e) {
        print('⚠️ Erro ao sincronizar exclusão de item: $e');
      }
    }
  }

  Future<int?> getIdCategoriaPromocao() async {
    return await _localDb.getIdCategoriaPromocao();
  }

  // ==========================================
  // STREAM DE ESTOQUE
  // ==========================================

  Stream<void> get estoqueStream => _localDb.estoqueStream;

  void notificarMudancaEstoque() {
    _localDb.notificarMudancaEstoque();
  }

  // ==========================================
  // VERSÃO DO BANCO DE DADOS
  // ==========================================

  Future<int> getDbVersion() async {
    return await _localDb.getDbVersion();
  }

  // ==========================================
  // MÉTODO PARA FECHAR O BANCO
  // ==========================================

  Future<void> close() async {
    await _localDb.close();
  }
}