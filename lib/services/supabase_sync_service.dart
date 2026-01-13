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
import 'package:sqflite/sqflite.dart';
import 'supabase_storage_service.dart';
import 'estoque_alerta_service.dart';
import 'notificacao_estoque_service.dart';



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
 final _storageService = SupabaseStorageService.instance;

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
  RealtimeChannel? _categoriasChannel;

  // ==========================================
  // INICIALIZAÇÃO
  // ==========================================

void _setupRealtimeListeners() {

// Listener para CATEGORIAS
_categoriasChannel = _supabase
    .channel('categorias_changes')
    .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'categorias',
      callback: (payload) async {
        print('🔔 Mudança detectada em categorias: ${payload.eventType}');
        
        // 🔥 Para DELETE, sempre sincronizar (não verificar device_id)
        if (payload.eventType == PostgresChangeEvent.delete) {
          print('🗑️ Categoria deletada - sincronizando...');
          await _syncCategorias();
          return;
        }
        
        // Para INSERT/UPDATE, evitar loop
        if (payload.newRecord?['device_id'] == _deviceId) {
          print('⏭️ Ignorando mudança criada por este dispositivo');
          return;
        }
        
        await _syncCategorias();
      },
    )
    .subscribe();

  // Listener para PRODUTOS
  _produtosChannel = _supabase
      .channel('produtos_changes')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'produtos',
        callback: (payload) async {
          print('🔔 Mudança detectada em produtos: ${payload.eventType}');
          
          if (payload.newRecord?['device_id'] == _deviceId) {
            print('⏭️ Ignorando mudança criada por este dispositivo');
            return;
          }
          
          await _syncProdutos();
        },
      )
      .subscribe();

  // Listener para PEDIDOS
  _pedidosChannel = _supabase
      .channel('pedidos_changes')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'pedidos',
        callback: (payload) async {
          print('🔔 Mudança detectada em pedidos: ${payload.eventType}');
          
          if (payload.newRecord?['device_id'] == _deviceId) {
            print('⏭️ Ignorando mudança criada por este dispositivo');
            return;
          }
          
          await _syncPedidos();
        },
      )
      .subscribe();
_supabase
      .channel('movimentos_estoque_changes')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'movimento_estoque',
        callback: (payload) async {
          print('🔔 Mudança detectada em movimentos de estoque: ${payload.eventType}');
          
          if (payload.newRecord?['device_id'] == _deviceId) {
            print('⏭️ Ignorando mudança criada por este dispositivo');
            return;
          }
          
          await _syncMovimentosEstoque();
        },
      )
      .subscribe();

  print('✅ Listeners Realtime configurados!');
}

  Future<void> initialize({String? estabelecimentoId}) async {
    try {
      print('🔄 Inicializando Supabase Sync Service...');
      
      _estabelecimentoId = estabelecimentoId;
      _deviceId = await _getOrCreateDeviceId();
      await _loadOfflineQueue();
      await _loadLastSyncTime();
      _setupConnectivityListener();
      
      // 🔥 COMENTADO: Listeners Realtime causam problemas sem estabelecimento_id
      _setupRealtimeListeners();

      

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

    // 🔥 ORDEM CORRETA: Categorias → Produtos → Usuários → Pedidos
    await _syncCategorias();      // 1º
    await _syncProdutos();        // 2º (depende de categorias)
    await _syncUsuarios();        // 3º
    await _syncPedidos();         // 4º (depende de produtos e usuários)
    await _syncMovimentosEstoque(); // 🔥 NOVO


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
// ADICIONAR ESTE MÉTODO:
// Localização: Método _syncUsuarios (linha ~170)
// SUBSTITUIR o método completo:

Future<void> _syncUsuarios() async {
  try {
    final response = await _supabase
        .from('usuario')
        .select('*')
        .order('id_usuario', ascending: true);

    final db = await _localDb.database;

    for (final usuarioMap in response) {
      final idUsuario = usuarioMap['id_usuario'] as int?;
      if (idUsuario == null) continue;
      
      final usuario = Usuario(
        id: idUsuario,
        nome: usuarioMap['nome'] as String,
        apelido: usuarioMap['apelido'] as String,
        email: usuarioMap['email'] as String,
        senhaHash: usuarioMap['senha_hash'] as String,
        telefone: usuarioMap['telefone'] as String?,
        dataCadastro: usuarioMap['data_cadastro'] as String,
        idProvincia: usuarioMap['idprovincia'] as int?,
        idCidade: usuarioMap['idcidade'] as int?,
        idPerfil: usuarioMap['idperfil'] as int?,
        primeiraSenha: usuarioMap['primeira_senha'] as int? ?? 1,
        ativo: usuarioMap['ativo'] as int? ?? 1,
      );

      // 🔥 SOLUÇÃO: Verificar se existe e usar UPDATE/INSERT separadamente
      final exists = await db.query(
        'usuario',
        where: 'id_usuario = ?',
        whereArgs: [idUsuario],
        limit: 1,
      );

      if (exists.isNotEmpty) {
        // Atualizar usuário existente
        await db.update(
          'usuario',
          usuario.toMap(),
          where: 'id_usuario = ?',
          whereArgs: [idUsuario],
        );
      } else {
        // Inserir novo usuário
        await db.insert('usuario', usuario.toMap());
      }
    }

    print('✅ ${response.length} usuários sincronizados');
  } catch (e) {
    print('❌ Erro ao sincronizar usuários: $e');
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

 // lib/services/supabase_sync_service.dart
// SUBSTITUA _syncProdutoFromSupabase:

Future<void> _syncProdutoFromSupabase(Map<String, dynamic> data) async {
  try {
    final idProduto = data['id_produto'] as int?;
    if (idProduto == null) return;
    
    // 1. Criar objeto Produto
    final produto = Produto(
      id: idProduto,
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

    // 2. Buscar categorias associadas
    final categoriasResponse = await _supabase
        .from('produto_categoria')
        .select('id_categoria')
        .eq('id_produto', idProduto);
    
    final db = await _localDb.database;
    final categoriasLocais = await db.query('categoria', columns: ['id_categoria']);
    final idsCategoriasLocais = categoriasLocais
        .map((c) => c['id_categoria'] as int)
        .toSet();
    
    final idsCategorias = categoriasResponse
        .map((c) => c['id_categoria'] as int)
        .where((id) => idsCategoriasLocais.contains(id))
        .toList();

    // 3. 🔥 BUSCAR IMAGENS E VALIDAR URLs
    final imagensResponse = await _supabase
        .from('produto_imagem')
        .select('*')
        .eq('id_produto', idProduto)
        .order('imagem_principal', ascending: false);
    
    final imagens = <ProdutoImagem>[];
    
    for (final img in imagensResponse) {
      final caminhoOriginal = img['caminho_imagem'] as String;
      String caminhoFinal = caminhoOriginal;
      
      // 🔥 VALIDAÇÃO: Se não for URL do Supabase, tentar baixar
      if (!_storageService.isSupabaseUrl(caminhoOriginal)) {
        print('⚠️ Caminho local detectado no Supabase: $caminhoOriginal');
        
        // Tentar criar URL pública a partir do nome do arquivo
        final nomeArquivo = caminhoOriginal.split('/').last;
        final urlPublica = _supabase.storage
            .from('produtos-imagens')
            .getPublicUrl(nomeArquivo);
        
        // Verificar se o arquivo existe no Storage
        try {
          await _supabase.storage
              .from('produtos-imagens')
              .download(nomeArquivo);
          
          caminhoFinal = urlPublica;
          print('✅ URL pública reconstruída: $urlPublica');
        } catch (e) {
          print('❌ Arquivo não existe no Storage: $nomeArquivo');
          // Manter caminho original (falhará, mas não quebra o sync)
        }
      }
      
      imagens.add(ProdutoImagem(
        id: img['id_imagem'] as int?,
        idProduto: idProduto,
        caminho: caminhoFinal, // 🔥 USA CAMINHO VALIDADO
        legenda: img['legenda'] as String?,
        isPrincipal: (img['imagem_principal'] as int?) == 1,
      ));
    }

    // 4. Verificar se produto existe localmente
    final existente = await _localDb.readProdutoWithDetailsById(idProduto);

    if (existente == null) {
      await _localDb.createProdutoComIdEspecifico(produto, idsCategorias, imagens);
    } else {
      await _localDb.updateProduto(produto, idsCategorias, imagens);
    }
    
    print('✅ Produto $idProduto sincronizado com ${imagens.length} imagens');
    
  } catch (e) {
    print('❌ Erro ao sincronizar produto ${data['id_produto']}: $e');
  }
}

// ===========================================
// 🔥 NOVO: MÉTODO PARA CORRIGIR IMAGENS EXISTENTES
// ===========================================

Future<void> corrigirImagensLocais() async {
  try {
    print('🔧 Iniciando correção de imagens com caminhos locais...');
    
    final produtos = await _localDb.readAllProdutosWithAssoc();
    int corrigidos = 0;
    
    for (final produto in produtos) {
      if (produto.imagens == null || produto.imagens!.isEmpty) continue;
      
      bool precisaAtualizar = false;
      final imagensCorrigidas = <ProdutoImagem>[];
      
      for (final imagem in produto.imagens!) {
        String caminhoFinal = imagem.caminho;
        
        // Se for caminho local, fazer upload
        if (!_storageService.isSupabaseUrl(imagem.caminho)) {
          print('📤 Fazendo upload de imagem local: ${imagem.caminho}');
          
          final urlPublica = await _storageService.uploadImagem(imagem.caminho);
          
          if (urlPublica != null) {
            caminhoFinal = urlPublica;
            precisaAtualizar = true;
            corrigidos++;
            print('✅ Upload concluído: $urlPublica');
          } else {
            print('⚠️ Falha no upload, mantendo caminho local');
          }
        }
        
        imagensCorrigidas.add(imagem.copyWith(caminho: caminhoFinal));
      }
      
      // Atualizar no Supabase se houver mudanças
      if (precisaAtualizar && _isOnline) {
        try {
          // Deletar imagens antigas
          await _supabase
              .from('produto_imagem')
              .delete()
              .eq('id_produto', produto.id!);
          
          // Inserir com URLs corretas
          for (final imagem in imagensCorrigidas) {
            await _supabase.from('produto_imagem').insert({
              'id_produto': produto.id!,
              'caminho_imagem': imagem.caminho,
              'legenda': imagem.legenda,
              'imagem_principal': imagem.isPrincipal ? 1 : 0,
            });
          }
          
          print('✅ Imagens do produto ${produto.id} atualizadas no Supabase');
        } catch (e) {
          print('❌ Erro ao atualizar imagens no Supabase: $e');
        }
      }
    }
    
    print('✅ Correção concluída! $corrigidos imagens foram enviadas para o Supabase');
    
    if (corrigidos > 0) {
      await syncAll(); // Sincronizar novamente
    }
    
  } catch (e) {
    print('❌ Erro na correção de imagens: $e');
  }
}


  // ==========================================
  // SINCRONIZAÇÃO DE CATEGORIAS
  // ==========================================

// lib/services/supabase_sync_service.dart

Future<void> _syncCategorias() async {
  try {
    final response = await _supabase
        .from('categorias')
        .select('*')
        .order('nome_categoria');

    // 🔥 NOVO: Buscar IDs locais para detectar exclusões
    final db = await _localDb.database;
    final categoriasLocais = await db.query(
      'categoria',
      columns: ['id_categoria'],
    );
    
    final idsLocais = categoriasLocais
        .map((c) => c['id_categoria'] as int)
        .toSet();
    
    final idsSupabase = response
        .map((c) => c['id_categoria'] as int)
        .toSet();
    
    // Deletar categorias que existem localmente mas não no Supabase
    final idsParaDeletar = idsLocais.difference(idsSupabase);
    for (final id in idsParaDeletar) {
      print('🗑️ Deletando categoria local $id (não existe no Supabase)');
      await db.delete(
        'categoria',
        where: 'id_categoria = ?',
        whereArgs: [id],
      );
    }

    for (final catMap in response) {
      final idCategoria = catMap['id_categoria'] as int?;
      if (idCategoria == null) continue;
      
      final categoria = Categoria(
        id: idCategoria,
        nome: catMap['nome_categoria'] as String? ?? 'Sem nome',
        descricao: catMap['descricao'] as String?,
      );

      final existente = await _localDb.readCategoriaWithProdutosById(idCategoria);

      if (existente == null) {
        await _localDb.createCategoriaComIdEspecifico(categoria, []);
      } else {
        await db.update(
          'categoria',
          {
            'nome_categoria': categoria.nome,
            'descricao': categoria.descricao,
          },
          where: 'id_categoria = ?',
          whereArgs: [idCategoria],
        );
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

    // Buscar todos os pedidos do Supabase
    final response = await _supabase
        .from('pedidos')
        .select('*')
        .gte('data_pedido', dataLimite.toIso8601String())
        .order('data_pedido', ascending: false);

    final db = await _localDb.database;

    // Sincronizar cada pedido localmente
    for (final pedidoMap in response) {
      final idPedido = pedidoMap['id_pedido'] as int?;
      if (idPedido == null) continue;

      // 🔥 CRÍTICO: Garantir que idtipo_pagamento NUNCA seja NULL
      final idTipoPagamento = pedidoMap['idtipo_pagamento'] as int?;
      if (idTipoPagamento == null) {
        print('⚠️ Pedido $idPedido sem tipo_pagamento - pulando sincronização');
        continue;
      }

      // Verificar se pedido já existe localmente
      final existente = await db.query(
        'pedido',
        where: 'id_pedido = ?',
        whereArgs: [idPedido],
        limit: 1,
      );

      // Construir dados com valores padrão
      final pedidoData = {
        'id_pedido': idPedido,
        'reference': pedidoMap['reference'],
        'id_usuario': pedidoMap['id_usuario'],
        'telefone': pedidoMap['telefone'],
        'email': pedidoMap['email'],
        'idtipo_pagamento': idTipoPagamento,
        'data_pedido': pedidoMap['data_pedido'],
        'data_fim_pedido': pedidoMap['data_fim_pedido'],
        'status_pedido': pedidoMap['status_pedido'] ?? 'por finalizar',
        'notificacao_vista': pedidoMap['notificacao_vista'] ?? 0,
        'total': pedidoMap['total'] ?? 0.0,
        'endereco_json': pedidoMap['endereco_json'],
        'valor_pago_manual': pedidoMap['valor_pago_manual'] ?? 0.0,
        'data_finalizacao': pedidoMap['data_finalizacao'],
        'bairro': pedidoMap['bairro'],
        'ponto_referencia': pedidoMap['ponto_referencia'],
        'troco': pedidoMap['troco'] ?? 0.0,
        'oculto_cliente': pedidoMap['oculto_cliente'] ?? 0,
      };

      if (existente.isEmpty) {
        await db.insert('pedido', pedidoData);
        print('✅ Pedido $idPedido inserido localmente');
      } else {
        await db.update(
          'pedido',
          pedidoData,
          where: 'id_pedido = ?',
          whereArgs: [idPedido],
        );
        print('✅ Pedido $idPedido atualizado localmente');
      }

      // 🔥 NOVO: Sincronizar itens COM VALIDAÇÃO de produtos
      try {
        final itensResponse = await _supabase
            .from('itens_pedido')
            .select('*')
            .eq('id_pedido', idPedido);

        // Deletar itens locais antigos
        await db.delete(
          'item_pedido',
          where: 'id_pedido = ?',
          whereArgs: [idPedido],
        );

        // 🔥 CORREÇÃO CRÍTICA: Validar produtos ANTES de inserir itens
        for (final itemMap in itensResponse) {
          final idProduto = itemMap['id_produto'] as int?;
          if (idProduto == null) {
            print('⚠️ Item sem id_produto no pedido $idPedido - pulando');
            continue;
          }

          // 🔥 VALIDAÇÃO: Verificar se o produto existe localmente
          final produtoExiste = await db.query(
            'produto',
            columns: ['id_produto', 'nome_produto'],
            where: 'id_produto = ?',
            whereArgs: [idProduto],
            limit: 1,
          );

          if (produtoExiste.isEmpty) {
            print('⚠️ Produto $idProduto não encontrado localmente - sincronizando produtos primeiro');
            
            // 🔥 SOLUÇÃO: Sincronizar o produto que está faltando
            try {
              final produtoResponse = await _supabase
                  .from('produtos')
                  .select('*')
                  .eq('id_produto', idProduto)
                  .single();
              
              await _syncProdutoFromSupabase(produtoResponse);
              print('✅ Produto $idProduto sincronizado durante sync de pedidos');
              
            } catch (e) {
              print('❌ Erro ao sincronizar produto $idProduto: $e');
              continue; // Pular este item se o produto não puder ser sincronizado
            }
          }

          // Agora SIM inserir o item (produto garantidamente existe)
          await db.insert('item_pedido', {
            'id_item_pedido': itemMap['id_item_pedido'],
            'id_pedido': idPedido,
            'id_produto': idProduto,
            'quantidade': itemMap['quantidade'],
            'preco_unitario': itemMap['preco_unitario'],
            'subtotal': itemMap['subtotal'],
          });
        }
        
        print('✅ ${itensResponse.length} itens sincronizados para pedido $idPedido');
        
        // 🔥 VALIDAÇÃO FINAL: Verificar se os dados estão completos
        final itensComProdutos = await db.rawQuery('''
          SELECT 
            ip.*,
            p.nome_produto,
            pi.caminho_imagem
          FROM item_pedido ip
          INNER JOIN produto p ON ip.id_produto = p.id_produto
          LEFT JOIN produto_imagem pi ON p.id_produto = pi.id_produto AND pi.imagem_principal = 1
          WHERE ip.id_pedido = ?
        ''', [idPedido]);
        
        // 🔥 LOG DE DIAGNÓSTICO (remover em produção)
        for (final item in itensComProdutos) {
          final nomeProduto = item['nome_produto'] as String?;
          final caminhoImagem = item['caminho_imagem'] as String?;
          print('   📦 Item: ${nomeProduto ?? "SEM NOME"} | Imagem: ${caminhoImagem != null ? "✅" : "❌"}');
        }
        
      } catch (e) {
        print('⚠️ Erro ao sincronizar itens do pedido $idPedido: $e');
      }
    }

    print('✅ ${response.length} pedidos sincronizados');
  } catch (e) {
    print('❌ Erro ao sincronizar pedidos: $e');
  }
}

// ==========================================
// SINCRONIZAÇÃO DE MOVIMENTOS DE ESTOQUE
// ==========================================

Future<void> _syncMovimentosEstoque() async {
  try {
    final dataLimite = DateTime.now().subtract(const Duration(days: 90)); // Últimos 90 dias

    final response = await _supabase
        .from('movimento_estoque')
        .select('*')
        .gte('data_movimento', dataLimite.toIso8601String())
        .order('data_movimento', ascending: false);

    final db = await _localDb.database;

    for (final movMap in response) {
      final idMovimento = movMap['id_movimento'] as int?;
      if (idMovimento == null) continue;

      final existente = await db.query(
        'movimento_estoque',
        where: 'id_movimento = ?',
        whereArgs: [idMovimento],
        limit: 1,
      );

      final movimentoData = {
        'id_movimento': idMovimento,
        'id_produto': movMap['id_produto'],
        'id_usuario': movMap['id_usuario'],
        'tipo_movimento': movMap['tipo_movimento'],
        'quantidade': movMap['quantidade'],
        'quantidade_anterior': movMap['quantidade_anterior'],
        'quantidade_nova': movMap['quantidade_nova'],
        'motivo': movMap['motivo'],
        'device_id': movMap['device_id'],
        'data_movimento': movMap['data_movimento'],
      };

      if (existente.isEmpty) {
        await db.insert('movimento_estoque', movimentoData);
        print('✅ Movimento $idMovimento inserido localmente');
      } else {
        await db.update(
          'movimento_estoque',
          movimentoData,
          where: 'id_movimento = ?',
          whereArgs: [idMovimento],
        );
        print('✅ Movimento $idMovimento atualizado localmente');
      }
    }

    print('✅ ${response.length} movimentos de estoque sincronizados');
  } catch (e) {
    print('❌ Erro ao sincronizar movimentos de estoque: $e');
  }
}


  // ==========================================
  // CRUD PRODUTOS (COM SYNC AUTOMÁTICO)
  // ==========================================

// lib/services/supabase_sync_service.dart
// SUBSTITUA o método createProduto completo:

Future<int> createProduto(
    Produto produto,
    List<int> idsCategorias,
    List<ProdutoImagem> imagens,
  ) async {
    if (_isOnline) {
      try {
        // 🔥 NOVO: Fazer upload das imagens ANTES de criar o produto
        final imagensComUrl = <ProdutoImagem>[];
        
        for (final imagem in imagens) {
          String? caminhoFinal = imagem.caminho;
          
          // Se for caminho local, fazer upload
          if (!_storageService.isSupabaseUrl(imagem.caminho)) {
            final urlPublica = await _storageService.uploadImagem(imagem.caminho);
            
            if (urlPublica != null) {
              caminhoFinal = urlPublica;
              print('✅ Upload: ${imagem.caminho} → $urlPublica');
            } else {
              print('⚠️ Falha no upload de ${imagem.caminho}, mantendo caminho local');
            }
          }
          
          imagensComUrl.add(imagem.copyWith(caminho: caminhoFinal));
        }

        // 1. Inserir produto no Supabase
        final response = await _supabase.from('produtos').insert({
          'nome_produto': produto.nome,
          'descricao': produto.descricao,
          'preco': produto.preco,
          'preco_promocional': produto.precoPromocional,
          'quantidade_estoque': produto.quantidadeEstoque ?? 0,
          'ativo': produto.ativo,
          'data_cadastro': produto.dataCadastro ?? DateTime.now().toIso8601String(),
          'device_id': _deviceId,
        }).select().single();

        final idSupabase = response['id_produto'] as int;
        print('✅ Produto criado no Supabase com ID: $idSupabase');
        
        // 2. Inserir categorias
        if (idsCategorias.isNotEmpty) {
          for (final idCategoria in idsCategorias) {
            await _supabase.from('produto_categoria').insert({
              'id_produto': idSupabase,
              'id_categoria': idCategoria,
            });
          }
        }
        
        // 3. Inserir imagens COM URLs DO SUPABASE
        if (imagensComUrl.isNotEmpty) {
          for (final imagem in imagensComUrl) {
            await _supabase.from('produto_imagem').insert({
              'id_produto': idSupabase,
              'caminho_imagem': imagem.caminho, // 🔥 AGORA É URL PÚBLICA
              'legenda': imagem.legenda,
              'imagem_principal': imagem.isPrincipal ? 1 : 0,
            });
          }
        }
        
        // 4. Criar localmente COM URLS
        final produtoComId = produto.copyWith(id: idSupabase);
        await _localDb.createProdutoComIdEspecifico(
          produtoComId,
          idsCategorias,
          imagensComUrl, // 🔥 USA IMAGENS COM URLS
        );

        return idSupabase;
        
      } catch (e) {
        print('❌ Erro ao criar no Supabase: $e');
        
        // Fallback: criar offline (será sincronizado depois)
        final idLocal = await _localDb.createProduto(produto, idsCategorias, imagens);
        _addToOfflineQueue(OfflineOperation(
          type: 'create_produto',
          data: {
            'produto': produto.copyWith(id: idLocal).toMap(),
            'categorias': idsCategorias,
            'imagens': imagens.map((i) => i.toMap()).toList(),
          },
          timestamp: DateTime.now(),
        ));
        return idLocal;
      }
    } else {
      // Offline: criar local
      final idLocal = await _localDb.createProduto(produto, idsCategorias, imagens);
      _addToOfflineQueue(OfflineOperation(
        type: 'create_produto',
        data: {
          'produto': produto.copyWith(id: idLocal).toMap(),
          'categorias': idsCategorias,
          'imagens': imagens.map((i) => i.toMap()).toList(),
        },
        timestamp: DateTime.now(),
      ));
      return idLocal;
    }
  }



  Future<int> updateProduto(
    Produto produto,
    List<int> idsCategorias,
    List<ProdutoImagem> imagens,
  ) async {
    // 🔥 FAZER UPLOAD DE NOVAS IMAGENS
    final imagensComUrl = <ProdutoImagem>[];
    
    for (final imagem in imagens) {
      String? caminhoFinal = imagem.caminho;
      
      if (!_storageService.isSupabaseUrl(imagem.caminho)) {
        final urlPublica = await _storageService.uploadImagem(imagem.caminho);
        
        if (urlPublica != null) {
          caminhoFinal = urlPublica;
        }
      }
      
      imagensComUrl.add(imagem.copyWith(caminho: caminhoFinal));
    }
    
    // 1. Atualizar localmente COM URLS
    final result = await _localDb.updateProduto(produto, idsCategorias, imagensComUrl);

    // 2. Sincronizar com Supabase
    if (_isOnline && produto.id != null) {
      try {
        await _supabase
            .from('produtos')
            .update({
              'nome_produto': produto.nome,
              'descricao': produto.descricao,
              'preco': produto.preco,
              'preco_promocional': produto.precoPromocional,
              'quantidade_estoque': produto.quantidadeEstoque,
              'ativo': produto.ativo,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id_produto', produto.id!);
        
        // Atualizar imagens no Supabase
        await _supabase
            .from('produto_imagem')
            .delete()
            .eq('id_produto', produto.id!);
        
        for (final imagem in imagensComUrl) {
          await _supabase.from('produto_imagem').insert({
            'id_produto': produto.id!,
            'caminho_imagem': imagem.caminho,
            'legenda': imagem.legenda,
            'imagem_principal': imagem.isPrincipal ? 1 : 0,
          });
        }
        
        print('✅ Produto ${produto.id} atualizado no Supabase');
      } catch (e) {
        print('⚠️ Erro ao sincronizar atualização: $e');
      }
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

  Future<int> toggleAtivoProduto(int idProduto, bool isActive) async {
  // 1. Atualizar localmente
  final result = await _localDb.toggleAtivoProduto(idProduto, isActive);
  
  // 2. Sincronizar com Supabase
  if (_isOnline) {
    try {
      await _supabase
          .from('produtos')
          .update({
            'ativo': isActive ? 1 : 0,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'device_id': _deviceId,
          })
          .eq('id_produto', idProduto);
      
      print('✅ Status do produto $idProduto atualizado no Supabase');
    } catch (e) {
      print('⚠️ Erro ao sincronizar status: $e');
      // Adicionar à fila offline se falhar
      _addToOfflineQueue(OfflineOperation(
        type: 'toggle_ativo_produto',
        data: {
          'id_produto': idProduto,
          'ativo': isActive ? 1 : 0,
        },
        timestamp: DateTime.now(),
      ));
    }
  } else {
    // Offline: adicionar à fila
    _addToOfflineQueue(OfflineOperation(
      type: 'toggle_ativo_produto',
      data: {
        'id_produto': idProduto,
        'ativo': isActive ? 1 : 0,
      },
      timestamp: DateTime.now(),
    ));
  }
  
  return result;
}



// ==========================================
// CRUD MOVIMENTOS DE ESTOQUE (COM SYNC)
// ==========================================


  // ==========================================
  // CRUD CATEGORIAS (COM SYNC)
  // ==========================================

 // lib/services/supabase_sync_service.dart

Future<int> createCategoria(Categoria categoria, List<int> idsProdutos) async {
  // Se ONLINE: Criar no Supabase PRIMEIRO
  if (_isOnline) {
    try {
      // 1. Inserir categoria no Supabase (SEM id_categoria)
   final response = await _supabase.from('categorias').insert({
  'nome_categoria': categoria.nome,
  'descricao': categoria.descricao,
  'device_id': _deviceId, // 🔥 ADICIONAR ESTA LINHA
}).select().single();

      final idSupabase = response['id_categoria'] as int;
      print('✅ Categoria criada no Supabase com ID: $idSupabase');
      
      // 2. Inserir associações produto_categoria no Supabase
      if (idsProdutos.isNotEmpty) {
        for (final idProduto in idsProdutos) {
          await _supabase.from('produto_categoria').insert({
            'id_produto': idProduto,
            'id_categoria': idSupabase,
          });
        }
      }
      
      // 3. Criar localmente COM ID DO SUPABASE
      final categoriaComId = categoria.copyWith(id: idSupabase);
      await _localDb.createCategoriaComIdEspecifico(categoriaComId, idsProdutos);

      return idSupabase;
      
    } catch (e) {
      print('❌ Erro ao criar categoria no Supabase: $e');
      // Fallback: criar offline
      return await _localDb.createCategoria(categoria, idsProdutos);
    }
  } else {
    // Offline: criar local
    return await _localDb.createCategoria(categoria, idsProdutos);
  }
}

// lib/services/supabase_sync_service.dart

Future<int> updateCategoria(Categoria categoria, List<int> idsProdutos) async {
  // 1. Atualizar localmente
  final result = await _localDb.updateCategoria(categoria, idsProdutos);

  // 2. Sincronizar com Supabase
  if (_isOnline && categoria.id != null) {
    try {
      // Atualizar categoria
      await _supabase
          .from('categorias')
          .update({
            'nome_categoria': categoria.nome,
            'descricao': categoria.descricao,
          })
          .eq('id_categoria', categoria.id!);
      
      // Atualizar associações: deletar antigas e inserir novas
      await _supabase
          .from('produto_categoria')
          .delete()
          .eq('id_categoria', categoria.id!);
      
      if (idsProdutos.isNotEmpty) {
        for (final idProduto in idsProdutos) {
          await _supabase.from('produto_categoria').insert({
            'id_produto': idProduto,
            'id_categoria': categoria.id!,
          });
        }
      }
      
      print('✅ Categoria ${categoria.id} atualizada no Supabase');
    } catch (e) {
      print('⚠️ Erro ao sincronizar categoria: $e');
    }
  }

  return result;
}

  // lib/services/supabase_sync_service.dart

// SUBSTITUIR o método completo:

// 🔥 SUBSTITUIR o método deleteCategoria completo:
Future<int> deleteCategoria(int idCategoria) async {
  // 1. Deletar localmente PRIMEIRO
  final result = await _localDb.deleteCategoria(idCategoria);
  
  // 2. Sincronizar com Supabase
  if (_isOnline) {
    try {
      // Deletar associações primeiro
      await _supabase
          .from('produto_categoria')
          .delete()
          .eq('id_categoria', idCategoria);
      
      // Depois deletar a categoria
      await _supabase
          .from('categorias')
          .delete()
          .eq('id_categoria', idCategoria);
      
      print('✅ Categoria $idCategoria deletada do Supabase');
      
      // Aguardar propagação do Realtime
      await Future.delayed(const Duration(milliseconds: 500));
      
    } catch (e) {
      print('❌ Erro ao deletar categoria no Supabase: $e');
      
      _addToOfflineQueue(OfflineOperation(
        type: 'delete_categoria',
        data: {'id_categoria': idCategoria},
        timestamp: DateTime.now(),
      ));
    }
  } else {
    // Adicionar à fila offline
    _addToOfflineQueue(OfflineOperation(
      type: 'delete_categoria',
      data: {'id_categoria': idCategoria},
      timestamp: DateTime.now(),
    ));
  }
  
  return result;
}


  // ==========================================
  // CRUD PEDIDOS (COM SYNC)
  // ==========================================

  // Localização: sync_service.dart, método createPedido (linha ~550)
// SUBSTITUIR completamente:

// 🔥 SUBSTITUIR o método createPedido completo:
// 🔥 SUBSTITUIR O MÉTODO COMPLETO createPedido:

Future<int> createPedido(Pedido pedido, List<ItemPedido> itens) async {
  // Validações
  if (pedido.idTipoPagamento == null) {
    throw Exception('Tipo de pagamento é obrigatório');
  }
  
  if (itens.isEmpty) {
    throw Exception('Pedido deve ter ao menos um item');
  }
  
  // Se OFFLINE: criar localmente
  if (!_isOnline) {
    return await _createPedidoOffline(pedido, itens);
  }
  
  // 🔥 NOVO: TESTAR QUALIDADE DA CONEXÃO ANTES
  try {
    print('🔍 Testando qualidade da conexão...');
    await _supabase
      .from('pedidos')
      .select('id_pedido')
      .limit(1)
      .timeout(const Duration(seconds: 2));
    print('✅ Conexão estável detectada');
    
  } on TimeoutException {
    print('⚠️ Conexão instável (timeout no ping) - criando offline');
    return await _createPedidoOffline(pedido, itens);
  } catch (e) {
    print('⚠️ Erro no teste de conexão: $e - criando offline');
    return await _createPedidoOffline(pedido, itens);
  }
  
  // ONLINE: Usar RPC
  try {
    final reference = 'PED-${DateTime.now().millisecondsSinceEpoch}';
    
    final itensJson = itens.map((item) => {
      'id_produto': item.idProduto,
      'quantidade': item.quantidade,
      'preco_unitario': item.precoUnitario,
      'subtotal': item.subtotal,
    }).toList();
    
    print('🔄 Criando pedido no Supabase...');
    
    // 🔥 TIMEOUT REDUZIDO: 10s → 5s
    final response = await _supabase.rpc('criar_pedido_completo', params: {
      'p_reference': reference,
      'p_id_usuario': pedido.idUsuario,
      'p_telefone': pedido.telefone,
      'p_email': pedido.email,
      'p_idtipo_pagamento': pedido.idTipoPagamento,
      'p_itens': itensJson,
    }).timeout(
      const Duration(seconds: 5), // ✅ REDUZIDO
      onTimeout: () => throw TimeoutException('Conexão instável - timeout na criação'),
    );
    
    final idSupabase = response[0]['id_pedido'] as int;
    final total = (response[0]['total'] as num).toDouble();
    
    print('✅ Pedido #$idSupabase criado via RPC | Total: MZN $total');
    
    // Criar localmente APÓS sucesso no Supabase
    final db = await _localDb.database;
    await db.transaction((txn) async {
      final pedidoComId = pedido.copyWith(
        id: idSupabase,
        reference: reference,
        total: total,
      );
      
      await txn.insert(
        'pedido', 
        pedidoComId.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      for (final item in itens) {
        final itemComId = item.copyWith(idPedido: idSupabase);
        await txn.insert(
          'item_pedido', 
          itemComId.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        
        // Debitar estoque local
        await txn.rawUpdate(
          'UPDATE produto SET quantidade_estoque = quantidade_estoque - ? WHERE id_produto = ?',
          [item.quantidade, item.idProduto],
        );
      }
    });
    
    // 🔥 NOVO: VALIDAR CONSISTÊNCIA DO ESTOQUE
    try {
      print('🔍 Validando consistência do estoque...');
      
      for (final item in itens) {
        final estoqueRemoto = await _supabase
          .from('produtos')
          .select('quantidade_estoque, nome_produto')
          .eq('id_produto', item.idProduto)
          .single()
          .timeout(const Duration(seconds: 3));
        
        final estoqueLocal = await db.query(
          'produto',
          columns: ['quantidade_estoque', 'nome_produto'],
          where: 'id_produto = ?',
          whereArgs: [item.idProduto],
        );
        
        if (estoqueLocal.isNotEmpty) {
          final qtdRemota = estoqueRemoto['quantidade_estoque'] as int;
          final qtdLocal = estoqueLocal.first['quantidade_estoque'] as int;
          final nomeProduto = estoqueLocal.first['nome_produto'] as String;
          
          if (qtdRemota != qtdLocal) {
            print('⚠️ INCONSISTÊNCIA DETECTADA: $nomeProduto');
            print('   Remoto: $qtdRemota | Local: $qtdLocal');
            
            // Corrigir estoque local para bater com o remoto
            await db.update(
              'produto',
              {'quantidade_estoque': qtdRemota},
              where: 'id_produto = ?',
              whereArgs: [item.idProduto],
            );
            print('✅ Estoque local corrigido: $nomeProduto → $qtdRemota');
          } else {
            print('✅ Estoque consistente: $nomeProduto ($qtdLocal)');
          }
        }
      }
      
    } catch (e) {
      print('⚠️ Não foi possível validar estoque: $e');
      // Não é crítico - pedido já foi criado com sucesso
    }
    
    return idSupabase;
    
  } on TimeoutException catch (e) {
    print('⏱️ Timeout: $e - criando offline');
    return await _createPedidoOffline(pedido, itens);
    
  } catch (e) {
    print('❌ Erro ao criar pedido: $e');
    
    // Se erro for de estoque, NÃO criar offline
    if (e.toString().contains('Estoque insuficiente') || 
        e.toString().contains('não encontrado')) {
      rethrow;
    }
    
    // Outros erros: criar offline
    return await _createPedidoOffline(pedido, itens);
  }
}

Future<int> _createPedidoOffline(Pedido pedido, List<ItemPedido> itens) async {
  print('📵 Modo offline - criando pedido localmente');
  
  try {
    final db = await _localDb.database;
    
    return await db.transaction((txn) async {
      final reference = 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}';
      
      // Criar mapa do pedido
      final pedidoMap = pedido.copyWith(
        reference: reference,
        statusPedido: 'por finalizar',
      ).toMap();
      
      // ✅ Garantir formato correto da data
      pedidoMap['data_pedido'] = DateTime.now().toIso8601String();
      
      // Remover id_pedido (deixa AUTOINCREMENT gerar)
      pedidoMap.remove('id_pedido');
      
      final idLocal = await txn.insert('pedido', pedidoMap);
      
      double totalCalculado = 0;
      
      // 🔥 VALIDAR ESTOQUE LOCAL ANTES DE DEBITAR
      for (final item in itens) {
        final produtoRows = await txn.query(
          'produto',
          columns: ['quantidade_estoque', 'nome_produto'],
          where: 'id_produto = ?',
          whereArgs: [item.idProduto],
        );
        
        if (produtoRows.isEmpty) {
          throw Exception('Produto ${item.idProduto} não encontrado localmente');
        }
        
        final estoqueLocal = produtoRows.first['quantidade_estoque'] as int;
        final nomeProduto = produtoRows.first['nome_produto'] as String;
        
        if (estoqueLocal < item.quantidade) {
          throw Exception(
            'Estoque insuficiente para "$nomeProduto".\n'
            'Disponível: $estoqueLocal | Solicitado: ${item.quantidade}'
          );
        }
      }
      
      // Se validação passou, inserir itens e debitar estoque
      for (final item in itens) {
        final itemMap = item.copyWith(idPedido: idLocal).toMap();
        itemMap.remove('id_item_pedido');
        
        await txn.insert('item_pedido', itemMap);
        
        // Debitar estoque local
        final rowsAffected = await txn.rawUpdate(
          'UPDATE produto SET quantidade_estoque = quantidade_estoque - ? WHERE id_produto = ?',
          [item.quantidade, item.idProduto],
        );
        
        if (rowsAffected == 0) {
          throw Exception('Falha ao debitar estoque do produto ${item.idProduto}');
        }
        
        print('✅ Estoque local debitado: produto ${item.idProduto} (-${item.quantidade})');
        
        totalCalculado += item.subtotal;
      }
      
      // Atualizar total
      await txn.update(
        'pedido',
        {'total': totalCalculado},
        where: 'id_pedido = ?',
        whereArgs: [idLocal],
      );
      
      print('✅ Pedido #$idLocal criado offline | Total: MZN $totalCalculado');
      print('📝 Será sincronizado quando conexão for restaurada');
      
      return idLocal;
    });
    
  } catch (e) {
    print('❌ ERRO ao criar pedido offline: $e');
    rethrow;
  }
}

// ==========================================
// ADICIONAR ITEM A PEDIDO EXISTENTE
// ==========================================


Future<void> adicionarItemAoPedido(
  int idPedido,
  int idProduto,
  int quantidade,
) async {
  if (quantidade < 1) {
    throw Exception('Quantidade deve ser maior que zero');
  }

  final db = await _localDb.database;
  
  await db.transaction((txn) async {
    // 1. Buscar dados do produto
    final produtoRows = await txn.rawQuery(
      'SELECT preco, quantidade_estoque, nome_produto FROM produto WHERE id_produto = ?',
      [idProduto],
    );
    
    if (produtoRows.isEmpty) {
      throw Exception('Produto não encontrado');
    }
    
    final row = produtoRows.first;
    final preco = (row['preco'] as num).toDouble();
    final estoqueDisponivel = row['quantidade_estoque'] as int?;
    final nomeProduto = row['nome_produto'] as String;
    
    // 2. Verificar estoque disponível
    if (estoqueDisponivel == null || estoqueDisponivel < quantidade) {
      throw Exception(
        'Estoque insuficiente para $nomeProduto.\n'
        'Disponível: ${estoqueDisponivel ?? 0} | Solicitado: $quantidade'
      );
    }
    
    // 3. Verificar se item já existe no pedido
    final itemExistente = await txn.rawQuery(
      'SELECT id_item_pedido, quantidade FROM item_pedido WHERE id_pedido = ? AND id_produto = ?',
      [idPedido, idProduto],
    );
    
    if (itemExistente.isNotEmpty) {
      // 🔥 ITEM JÁ EXISTE: Incrementar quantidade
      final idItem = itemExistente.first['id_item_pedido'] as int;
      final quantidadeAtual = itemExistente.first['quantidade'] as int;
      final novaQuantidade = quantidadeAtual + quantidade;
      final novoSubtotal = novaQuantidade * preco;
      
      await txn.update(
        'item_pedido',
        {
          'quantidade': novaQuantidade,
          'subtotal': novoSubtotal,
        },
        where: 'id_item_pedido = ?',
        whereArgs: [idItem],
      );
      
      print('✅ Item atualizado: $nomeProduto (${quantidadeAtual} → $novaQuantidade)');
      
      // Sincronizar com Supabase
      if (_isOnline) {
        await _supabase.from('itens_pedido').update({
          'quantidade': novaQuantidade,
          'subtotal': novoSubtotal,
        }).eq('id_item_pedido', idItem);
      }
      
    } else {
      // 🔥 ITEM NOVO: Inserir
      final subtotal = quantidade * preco;
      
      final idItemLocal = await txn.insert('item_pedido', {
        'id_pedido': idPedido,
        'id_produto': idProduto,
        'quantidade': quantidade,
        'preco_unitario': preco,
        'subtotal': subtotal,
      });
      
      print('✅ Novo item adicionado: $nomeProduto (x$quantidade)');
      
      // Sincronizar com Supabase
      if (_isOnline) {
        await _supabase.from('itens_pedido').insert({
          'id_item_pedido': idItemLocal,
          'id_pedido': idPedido,
          'id_produto': idProduto,
          'quantidade': quantidade,
          'preco_unitario': preco,
          'subtotal': subtotal,
        });
      }
    }
    
    // 4. 🔥 DÉBITO DE ESTOQUE (sempre executado)
    await txn.rawUpdate(
      'UPDATE produto SET quantidade_estoque = quantidade_estoque - ? WHERE id_produto = ?',
      [quantidade, idProduto],
    );
    
    print('📦 Estoque debitado: $nomeProduto (-$quantidade)');
    
    // Sincronizar estoque no Supabase
    if (_isOnline) {
      await _supabase.rpc('decrement_stock', params: {
        'product_id': idProduto,
        'quantity': quantidade,
      });
    }
    
    // 5. Recalcular total do pedido
   // 5. 🔥 CRÍTICO: Recalcular total do pedido LOCALMENTE
final totalResult = await txn.rawQuery(
  'SELECT SUM(subtotal) as total FROM item_pedido WHERE id_pedido = ?',
  [idPedido],
);

final total = (totalResult.first['total'] as num?)?.toDouble() ?? 0.0;

await txn.update(
  'pedido',
  {'total': total},
  where: 'id_pedido = ?',
  whereArgs: [idPedido],
  );
if (_isOnline) {
  try {
    await _supabase.from('pedidos').update({
      'total': total,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id_pedido', idPedido);
    
    print('✅ Total sincronizado com Supabase: MZN ${total.toStringAsFixed(2)}');
  } catch (e) {
    print('⚠️ Erro ao sincronizar total: $e');
  }
}
print('💰 Total do pedido recalculado localmente: MZN ${total.toStringAsFixed(2)}');
  });

  
  
  notificarMudancaEstoque();
}
// ==========================================
// ATUALIZAR QUANTIDADE DE ITEM EXISTENTE
// ==========================================

Future<void> updateQuantidadeItem(int idItemPedido, int novaQuantidade) async {
  if (novaQuantidade < 1) {
    throw Exception('Quantidade deve ser maior que zero');
  }

  final db = await _localDb.database;
  
  await db.transaction((txn) async {
    // 1. Buscar item atual
    final itemMaps = await txn.query(
      'item_pedido',
      where: 'id_item_pedido = ?',
      whereArgs: [idItemPedido],
    );
    
    if (itemMaps.isEmpty) {
      throw Exception('Item não encontrado');
    }
    
    final itemAtual = ItemPedido.fromMap(itemMaps.first);
    final diferencaQuantidade = novaQuantidade - itemAtual.quantidade;
    
    print('📊 Alterando quantidade: ${itemAtual.quantidade} → $novaQuantidade (diff: $diferencaQuantidade)');
    
    // 2. 🔥 CORREÇÃO: Verificar estoque SOMENTE se AUMENTAR quantidade
    if (diferencaQuantidade > 0) {
      final produtoRows = await txn.query(
        'produto',
        columns: ['quantidade_estoque', 'nome_produto'],
        where: 'id_produto = ?',
        whereArgs: [itemAtual.idProduto],
      );
      
      if (produtoRows.isNotEmpty) {
        final estoqueDisponivel = produtoRows.first['quantidade_estoque'] as int?;
        final nomeProduto = produtoRows.first['nome_produto'] as String;
        
        if (estoqueDisponivel == null || estoqueDisponivel < diferencaQuantidade) {
          throw Exception(
            'Estoque insuficiente para $nomeProduto.\n'
            'Disponível: ${estoqueDisponivel ?? 0} | Solicitado: $diferencaQuantidade'
          );
        }
      }
    }
    
    // 3. Atualizar item
    final novoSubtotal = novaQuantidade * itemAtual.precoUnitario;
    
    await txn.update(
      'item_pedido',
      {
        'quantidade': novaQuantidade,
        'subtotal': novoSubtotal,
      },
      where: 'id_item_pedido = ?',
      whereArgs: [idItemPedido],
    );
    
    // 4. 🔥 CORREÇÃO CRÍTICA: Ajustar estoque CORRETAMENTE pela diferença
    if (diferencaQuantidade != 0) {
      await txn.rawUpdate(
        'UPDATE produto SET quantidade_estoque = quantidade_estoque - ? WHERE id_produto = ?',
        [diferencaQuantidade, itemAtual.idProduto],
      );
      
      print('📦 Estoque ajustado: produto ${itemAtual.idProduto} (diff: $diferencaQuantidade)');
    }
    
    // 5. Recalcular total do pedido
    final totalResult = await txn.rawQuery(
      'SELECT SUM(subtotal) as total FROM item_pedido WHERE id_pedido = ?',
      [itemAtual.idPedido],
    );
    
    final total = (totalResult.first['total'] as num?)?.toDouble() ?? 0.0;
    
    await txn.update(
      'pedido',
      {'total': total},
      where: 'id_pedido = ?',
      whereArgs: [itemAtual.idPedido],
    );
    
    print('💰 Total do pedido recalculado: MZN ${total.toStringAsFixed(2)}');
  }); // 🔥 FIM DA TRANSAÇÃO AQUI
  
  // 🔥 SINCRONIZAÇÃO FORA DA TRANSAÇÃO (usando a variável db já declarada)
  if (_isOnline) {
    try {
      // Buscar item novamente para pegar o idPedido
      final itemMapsForSync = await db.query(
        'item_pedido',
        where: 'id_item_pedido = ?',
        whereArgs: [idItemPedido],
      );
      
      if (itemMapsForSync.isNotEmpty) {
        final itemParaSync = ItemPedido.fromMap(itemMapsForSync.first);
        
        // Sincronizar item atualizado
        await _supabase.from('itens_pedido').update({
          'quantidade': itemParaSync.quantidade,
          'subtotal': itemParaSync.subtotal,
        }).eq('id_item_pedido', idItemPedido);
        
        // Buscar e sincronizar estoque atualizado
        final produtoRows = await db.query(
          'produto',
          columns: ['quantidade_estoque'],
          where: 'id_produto = ?',
          whereArgs: [itemParaSync.idProduto],
        );
        
        if (produtoRows.isNotEmpty) {
          final estoqueAtualizado = produtoRows.first['quantidade_estoque'] as int;
          await _supabase.from('produtos').update({
            'quantidade_estoque': estoqueAtualizado,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id_produto', itemParaSync.idProduto);
        }
        
        // Buscar e sincronizar total atualizado
        final pedidoAtualizado = await db.query(
          'pedido',
          columns: ['total'],
          where: 'id_pedido = ?',
          whereArgs: [itemParaSync.idPedido],
        );
        
        if (pedidoAtualizado.isNotEmpty) {
          final totalAtualizado = pedidoAtualizado.first['total'] as double;
          
          await _supabase.from('pedidos').update({
            'total': totalAtualizado,
           'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id_pedido', itemParaSync.idPedido);
          
          print('✅ Item, estoque e total sincronizados com Supabase');
        }
      }
    } catch (e) {
      print('⚠️ Erro ao sincronizar: $e');
    }
  }
  
  notificarMudancaEstoque();
}




// Localização: sync_service.dart, linha ~600
// SUBSTITUIR método completo:

// 🔥 SUBSTITUIR o método completo:
Future<void> cancelarPedido(int idPedido, String motivo, int idUsuarioCancelou) async {
  if (_isOnline) {
    try {
      // Buscar itens para reverter estoque
      final itensResponse = await _supabase
          .from('itens_pedido')
          .select('id_produto, quantidade')
          .eq('id_pedido', idPedido);
      
      // Reverter estoque NO SUPABASE
      for (final item in itensResponse) {
        await _supabase.rpc('increment_stock', params: {
          'product_id': item['id_produto'],
          'quantity': item['quantidade'],
        });
      }
      
      // Atualizar status COM DEVICE_ID para evitar loop
      await _supabase
          .from('pedidos')
          .update({
            'status_pedido': 'cancelado',
            'data_finalizacao': DateTime.now().toUtc().toIso8601String(),
            'device_id': _deviceId, // 🔥 ADICIONAR
          })
          .eq('id_pedido', idPedido);
      
      print('✅ Pedido $idPedido cancelado (device: $_deviceId)');
      
    } catch (e) {
      print('⚠️ Erro ao cancelar no Supabase: $e');
      _addToOfflineQueue(OfflineOperation(
        type: 'cancelar_pedido',
        data: {
          'id_pedido': idPedido,
          'motivo': motivo,
          'id_usuario_cancelou': idUsuarioCancelou,
        },
        timestamp: DateTime.now(),
      ));
    }
  }

  // 2. Cancelar localmente
  await _localDb.cancelarPedido(idPedido, motivo, idUsuarioCancelou);
}

// Localização: sync_service.dart, linha ~650
// SUBSTITUIR método completo:

// 🔥 MESMO ARQUIVO, linha ~680:
Future<void> finalizarPedido(
  int idPedido,
  int idTipoPagamento, {
  double? valorPago,
  double? troco,
}) async {
  // 1. 🔥 FINALIZAR NO SUPABASE PRIMEIRO
  if (_isOnline) {
    try {
      await _supabase
          .from('pedidos')
          .update({
            'status_pedido': 'finalizado',
            'idtipo_pagamento': idTipoPagamento,
            'valor_pago_manual': valorPago,
            'troco': troco,
            'data_finalizacao': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id_pedido', idPedido);
      
      print('✅ Pedido $idPedido finalizado no Supabase');
      
    } catch (e) {
      print('⚠️ Erro ao finalizar no Supabase: $e');
    }
  }

  // 2. Finalizar localmente
  await _localDb.finalizarPedido(
    idPedido,
    idTipoPagamento,
    valorPago: valorPago,
    troco: troco,
  );
  
  
}  // ==========================================
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
  // 🔥 GARANTIR SINCRONIZAÇÃO ANTES DE LER
  if (_isOnline) {
    await _syncPedidos();
  }
  
  // 🔥 FILTRAR POR USUÁRIO
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

        // ==========================================
// lib/services/supabase_sync_service.dart
// MÉTODO: _processOfflineOperation (linha ~740)
// ADICIONE ESTES CASES NO SWITCH:
// ==========================================

case 'create_usuario':
  final usuario = Usuario.fromMap(operation.data['usuario']);
  await _supabase.from('usuario').insert({  // ✅ MUDOU: 'usuario'
    'id_usuario': usuario.id,
    'nome': usuario.nome,
    'apelido': usuario.apelido,
    'email': usuario.email,
    'senha_hash': usuario.senhaHash,
    'telefone': usuario.telefone,
    'data_cadastro': usuario.dataCadastro,
    'idperfil': usuario.idPerfil,
    'ativo': usuario.ativo,
  });
  break;

case 'update_usuario':
  final usuario = Usuario.fromMap(operation.data['usuario']);
  if (usuario.id != null) {
    await _supabase
        .from('usuario')  // ✅ MUDOU: 'usuario'
        .update({
          'nome': usuario.nome,
          'apelido': usuario.apelido,
          'email': usuario.email,
          'senha_hash': usuario.senhaHash,
          'telefone': usuario.telefone,
          'ativo': usuario.ativo,
        })
        .eq('id_usuario', usuario.id!);
  }
  break;

case 'delete_usuario':
  final idUsuario = operation.data['id_usuario'] as int;
  await _supabase
      .from('usuario')  // ✅ MUDOU: 'usuario'
      .delete()
      .eq('id_usuario', idUsuario);
  break;

// ==========================================
// ADICIONAR CASES DE CATEGORIA
// ==========================================

case 'create_categoria':
  final categoriaData = operation.data['categoria'];
  final categoria = Categoria.fromMap(categoriaData);
  
   final response = await _supabase.from('categorias').insert({
    'nome_categoria': categoria.nome,
    'descricao': categoria.descricao,
    'device_id': _deviceId, // 🔥 ADICIONAR ESTA LINHA
  }).select().single();
  
  final idSupabase = response['id_categoria'] as int;
  
  final idsProdutos = operation.data['produtos'] as List<dynamic>?;
  if (idsProdutos != null && idsProdutos.isNotEmpty) {
    for (final idProduto in idsProdutos) {
      await _supabase.from('produto_categoria').insert({
        'id_produto': idProduto,
        'id_categoria': idSupabase,
      });
    }
  }
  break;

case 'update_categoria':
  final categoria = Categoria.fromMap(operation.data['categoria']);
  if (categoria.id != null) {
    await _supabase
        .from('categorias')
        .update({
          'nome_categoria': categoria.nome,
          'descricao': categoria.descricao,
        })
        .eq('id_categoria', categoria.id!);
  }
  break;

case 'delete_categoria':
  final idCategoria = operation.data['id_categoria'] as int;
  await _supabase
      .from('categorias')
      .delete()
      .eq('id_categoria', idCategoria);
  break;
case 'cancelar_pedido':
  final idPedido = operation.data['id_pedido'] as int;
  final motivo = operation.data['motivo'] as String;
  final idUsuario = operation.data['id_usuario_cancelou'] as int;
  
  await cancelarPedido(idPedido, motivo, idUsuario);
  break;

case 'finalizar_pedido':
  final idPedido = operation.data['id_pedido'] as int;
  final idTipoPagamento = operation.data['idtipo_pagamento'] as int;
  
  await finalizarPedido(
    idPedido,
    idTipoPagamento,
    valorPago: operation.data['valor_pago_manual'] as double?,
    troco: operation.data['troco'] as double?,
  );
  break;

  case 'toggle_ativo_produto':
  final idProduto = operation.data['id_produto'] as int;
  final ativo = operation.data['ativo'] as int;
  
  await _supabase
      .from('produtos')
      .update({
        'ativo': ativo,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'device_id': _deviceId,
      })
      .eq('id_produto', idProduto);
  break;


  // 🔥 ADICIONAR ESTE CASE no switch de _processOfflineOperation:

case 'create_pedido_completo':
  try {
    final pedidoData = operation.data['pedido'] as Map<String, dynamic>;
    final itensData = operation.data['itens'] as List<dynamic>;
    final idPedidoLocal = operation.data['id_pedido_local'] as int;
    
    final reference = 'PED-${DateTime.now().millisecondsSinceEpoch}';
    
    // Criar pedido no Supabase
    final pedidoResponse = await _supabase.from('pedidos').insert({
      'reference': reference,
      'id_usuario': pedidoData['id_usuario'],
      'total': pedidoData['total'],
      'status_pedido': 'por finalizar',
      'data_pedido': DateTime.now().toUtc().toIso8601String(),
      'telefone': pedidoData['telefone'],
      'email': pedidoData['email'],
      'idtipo_pagamento': pedidoData['idtipo_pagamento'],
      'device_id': _deviceId,
    }).select().single();
    
    final idSupabase = pedidoResponse['id_pedido'] as int;
    
    // Inserir itens
    for (final itemData in itensData) {
      await _supabase.from('itens_pedido').insert({
        'id_pedido': idSupabase,
        'id_produto': itemData['id_produto'],
        'quantidade': itemData['quantidade'],
        'preco_unitario': itemData['preco_unitario'],
        'subtotal': itemData['subtotal'],
      });
      
      // Debitar estoque
      await _supabase.rpc('decrement_stock', params: {
        'product_id': itemData['id_produto'],
        'quantity': itemData['quantidade'],
      });
    }
    
    // Atualizar ID local para ID do Supabase
    final db = await _localDb.database;
    await db.update(
      'pedido',
      {'id_pedido': idSupabase, 'reference': reference},
      where: 'id_pedido = ?',
      whereArgs: [idPedidoLocal],
    );
    
    await db.update(
      'item_pedido',
      {'id_pedido': idSupabase},
      where: 'id_pedido = ?',
      whereArgs: [idPedidoLocal],
    );

    
    print('✅ Pedido offline #$idPedidoLocal sincronizado como #$idSupabase');
    
  } catch (e) {
    print('❌ Erro ao sincronizar pedido offline: $e');
    rethrow; // Mantém na fila para próxima tentativa
  }
  break;

  case 'delete_item_pedido':
  try {
    final idItemPedido = operation.data['id_item_pedido'] as int;
    final idPedido = operation.data['id_pedido'] as int;
    final idProduto = operation.data['id_produto'] as int;
    final quantidade = operation.data['quantidade'] as int;
    
    print('🔄 Processando exclusão offline: item #$idItemPedido');
    
    // Deletar item no Supabase
    await _supabase
        .from('itens_pedido')
        .delete()
        .eq('id_item_pedido', idItemPedido);
    
    // Restituir estoque
    await _supabase.rpc('increment_stock', params: {
      'product_id': idProduto,
      'quantity': quantidade,
    });
    
    // Recalcular total
    final db = await _localDb.database;
    final pedidoAtualizado = await db.query(
      'pedido',
      columns: ['total'],
      where: 'id_pedido = ?',
      whereArgs: [idPedido],
    );
    
    if (pedidoAtualizado.isNotEmpty) {
      final totalAtualizado = pedidoAtualizado.first['total'] as double;
      
      await _supabase.from('pedidos').update({
        'total': totalAtualizado,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'device_id': _deviceId,
      }).eq('id_pedido', idPedido);
    }
    
    print('✅ Exclusão offline processada com sucesso');
    
  } catch (e) {
    print('❌ Erro ao processar exclusão offline: $e');
    rethrow; // Mantém na fila para próxima tentativa
  }
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
  _categoriasChannel?.unsubscribe(); // 🔥 ADICIONAR
  _statusStreamController.close();
  _erroStreamController.close();
}




// ==========================================
// CRUD USUÁRIOS (COM SYNC AUTOMÁTICO)
// ==========================================

// lib/services/supabase_sync_service.dart

Future<Usuario> createUsuario(Usuario usuario) async {
  if (_isOnline) {
    try {
      // 1. Inserir no Supabase (SEM id_usuario)
      final response = await _supabase.from('usuario').insert({
        'nome': usuario.nome,
        'apelido': usuario.apelido,
        'email': usuario.email,
        'senha_hash': usuario.senhaHash,
        'telefone': usuario.telefone,
        'data_cadastro': usuario.dataCadastro,
        'idprovincia': usuario.idProvincia,
        'idcidade': usuario.idCidade,
        'idperfil': usuario.idPerfil,
        'primeira_senha': usuario.primeiraSenha,
        'ativo': usuario.ativo,
      }).select().single();

      final idSupabase = response['id_usuario'] as int;
      print('✅ Usuário criado no Supabase com ID: $idSupabase');
      
      // 2. Criar localmente COM ID DO SUPABASE
      final usuarioComId = usuario.copyWith(id: idSupabase);
      final db = await _localDb.database;
      await db.insert('usuario', usuarioComId.toMap());

      return usuarioComId;
      
    } catch (e) {
      print('❌ Erro ao criar usuário no Supabase: $e');
      // Fallback: criar offline
      return await _localDb.createUsuario(usuario);
    }
  } else {
    return await _localDb.createUsuario(usuario);
  }
}


Future<int> updateUsuario(Usuario usuario) async {
  // 1. Atualizar localmente
  final result = await _localDb.updateUsuario(usuario);
  
  // 2. Sincronizar com Supabase
  if (_isOnline && usuario.id != null) {
    try {
      await _supabase
          .from('usuario') // 🔥 CORRIGIDO: 'usuario' (singular no schema)
          .update({
            'nome': usuario.nome,
            'apelido': usuario.apelido,
            'email': usuario.email,
            'senha_hash': usuario.senhaHash,
            'telefone': usuario.telefone,
            'idperfil': usuario.idPerfil,
            'primeira_senha': usuario.primeiraSenha,
            'ativo': usuario.ativo,
          })
          .eq('id_usuario', usuario.id!);
      print('✅ Usuário ${usuario.id} atualizado no Supabase');
    } catch (e) {
      print('⚠️ Erro ao sincronizar atualização: $e');
    }
  }
  
  return result;
}

Future<int> deleteUsuario(int id) async {
  // 1. Deletar localmente
  final result = await _localDb.deleteUsuario(id);
  
  // 2. Sincronizar com Supabase
  if (_isOnline) {
    try {
      await _supabase
          .from('usuario') // 🔥 CORRIGIDO
          .delete()
          .eq('id_usuario', id);
      print('✅ Usuário $id deletado do Supabase');
    } catch (e) {
      print('⚠️ Erro ao sincronizar exclusão: $e');
    }
  }
  
  return result;
}

Future<int> toggleAtivoUsuario(int id, bool isActive) async {
  final result = await _localDb.toggleAtivoUsuario(id, isActive);
  
  if (_isOnline) {
    try {
      await _supabase
          .from('usuario')  // ✅ CORRETO
          .update({
            'ativo': isActive ? 1 : 0,
          })
          .eq('id_usuario', id);
      print('✅ Status do usuário $id atualizado no Supabase');
    } catch (e) {
      print('⚠️ Erro ao sincronizar status: $e');
    }
  }
  
  return result;
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

 

  Future<List<Usuario>> readAllUsuarios() async {
    return await _localDb.readAllUsuarios();
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

  

// SUBSTITUIR o método completo:

Future<void> deleteItemPedido(int idItemPedido) async {
  final db = await _localDb.database;
  
  // 🔥 CRÍTICO: Buscar dados do item ANTES de qualquer operação
  final itemMaps = await db.query(
    'item_pedido',
    where: 'id_item_pedido = ?',
    whereArgs: [idItemPedido],
  );
  
  if (itemMaps.isEmpty) {
    throw Exception('Item não encontrado');
  }
  
  final item = ItemPedido.fromMap(itemMaps.first);
  final idPedido = item.idPedido;
  final idProduto = item.idProduto;
  final quantidade = item.quantidade;
  
  print('🗑️ Removendo item #$idItemPedido: Produto $idProduto (${quantidade}x)');
  
  // 🔥 EXECUTAR TUDO DENTRO DE UMA TRANSAÇÃO LOCAL
  await db.transaction((txn) async {
    // 1. RESTITUIR ESTOQUE LOCAL
    await txn.rawUpdate(
      'UPDATE produto SET quantidade_estoque = quantidade_estoque + ? WHERE id_produto = ?',
      [quantidade, idProduto],
    );
    
    print('📦 Estoque local restituído: produto $idProduto (+$quantidade)');
    
    // 2. DELETAR ITEM
    await txn.delete(
      'item_pedido',
      where: 'id_item_pedido = ?',
      whereArgs: [idItemPedido],
    );
    
    print('✅ Item #$idItemPedido deletado localmente');
    
    // 3. RECALCULAR TOTAL DO PEDIDO
    final totalResult = await txn.rawQuery(
      'SELECT SUM(subtotal) as total FROM item_pedido WHERE id_pedido = ?',
      [idPedido],
    );
    
    final total = (totalResult.first['total'] as num?)?.toDouble() ?? 0.0;
    
    await txn.update(
      'pedido',
      {'total': total},
      where: 'id_pedido = ?',
      whereArgs: [idPedido],
    );
    
    print('💰 Total do pedido recalculado: MZN ${total.toStringAsFixed(2)}');
    
    // 4. SE NÃO RESTAREM ITENS, DELETAR O PEDIDO
    final countResult = await txn.rawQuery(
      'SELECT COUNT(*) as count FROM item_pedido WHERE id_pedido = ?',
      [idPedido],
    );
    
    final count = countResult.first['count'] as int;
    if (count == 0) {
      await txn.delete(
        'pedido',
        where: 'id_pedido = ?',
        whereArgs: [idPedido],
      );
      print('🗑️ Pedido $idPedido deletado (sem itens restantes)');
    }
  }); // 🔥 FIM DA TRANSAÇÃO LOCAL
  
  // 🔥 SINCRONIZAR COM SUPABASE (FORA DA TRANSAÇÃO)
  if (_isOnline) {
    try {
      print('🌐 Iniciando sincronização com Supabase...');
      
      // 1. Deletar item no Supabase
      await _supabase
          .from('itens_pedido')
          .delete()
          .eq('id_item_pedido', idItemPedido);
      
      print('✅ Item #$idItemPedido deletado no Supabase');
      
      // 2. Restituir estoque no Supabase
      await _supabase.rpc('increment_stock', params: {
        'product_id': idProduto,
        'quantity': quantidade,
      });
      
      print('✅ Estoque restituído no Supabase: produto $idProduto (+$quantidade)');
      
      // 3. Buscar total atualizado e sincronizar
      final pedidoAtualizado = await db.query(
        'pedido',
        columns: ['total'],
        where: 'id_pedido = ?',
        whereArgs: [idPedido],
      );
      
      if (pedidoAtualizado.isNotEmpty) {
        final totalAtualizado = pedidoAtualizado.first['total'] as double;
        
        await _supabase.from('pedidos').update({
          'total': totalAtualizado,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'device_id': _deviceId,
        }).eq('id_pedido', idPedido);
        
        print('✅ Total do pedido sincronizado: MZN ${totalAtualizado.toStringAsFixed(2)}');
      }
      
      // 4. Se o pedido foi deletado localmente, deletar no Supabase
      final pedidoExiste = await db.query(
        'pedido',
        where: 'id_pedido = ?',
        whereArgs: [idPedido],
      );
      
      if (pedidoExiste.isEmpty) {
        await _supabase
            .from('pedidos')
            .delete()
            .eq('id_pedido', idPedido);
        
        print('✅ Pedido $idPedido deletado no Supabase (sem itens)');
      }
      
      print('✅ Sincronização completa com Supabase concluída!');
      
    } catch (e) {
      print('⚠️ Erro ao sincronizar com Supabase: $e');
      
      // 🔥 ADICIONAR À FILA OFFLINE
      _addToOfflineQueue(OfflineOperation(
        type: 'delete_item_pedido',
        data: {
          'id_item_pedido': idItemPedido,
          'id_pedido': idPedido,
          'id_produto': idProduto,
          'quantidade': quantidade,
        },
        timestamp: DateTime.now(),
      ));
      
      print('📝 Operação adicionada à fila offline');
    }
  } else {
    // 🔥 MODO OFFLINE: Adicionar à fila
    print('📵 Modo offline - adicionando à fila de sincronização');
    
    _addToOfflineQueue(OfflineOperation(
      type: 'delete_item_pedido',
      data: {
        'id_item_pedido': idItemPedido,
        'id_pedido': idPedido,
        'id_produto': idProduto,
        'quantidade': quantidade,
      },
      timestamp: DateTime.now(),
    ));
  }
  
  // 🔥 NOTIFICAR MUDANÇAS
  notificarMudancaEstoque();
  
  print('✅ deleteItemPedido concluído!');
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

// ADICIONAR este método no final da classe SupabaseSyncService (antes do último })
// Aproximadamente na linha 900

// ==========================================
// FORÇAR SINCRONIZAÇÃO APÓS OPERAÇÕES CRUD
// ==========================================

Future<void> forcarSincronizacaoCompleta() async {
  if (!_isOnline) {
    print('⚠️ Dispositivo offline - sincronização adiada');
    return;
  }
  
  try {
    print('🔄 Forçando sincronização completa após operação CRUD...');
    await syncAll();
    print('✅ Sincronização forçada concluída');
  } catch (e) {
    print('❌ Erro na sincronização forçada: $e');
  }
}


  // ==========================================
  // MÉTODO PARA FECHAR O BANCO
  // ==========================================

  Future<void> close() async {
    await _localDb.close();
  }
}

