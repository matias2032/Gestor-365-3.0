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
import 'sync_events_service.dart';
import 'dart:math';




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
  RealtimeChannel? _movimentosChannel;

  // ==========================================
  // INICIALIZAÇÃO
  // ==========================================



 Future<void> initialize({String? estabelecimentoId}) async {
  try {
    print('🔄 Inicializando Supabase Sync Service...');
    
    _estabelecimentoId = estabelecimentoId;
    _deviceId = await _getOrCreateDeviceId();
    await _loadLastSyncTime();
    
    // ✅ CARREGAR E VALIDAR FILA OFFLINE
    await _loadOfflineQueue();
    await validarFilaOffline();
    
    // ✅ PROCESSAR FILA SE HOUVER OPERAÇÕES PENDENTES
    if (_offlineQueue.isNotEmpty) {
      print('📤 ${_offlineQueue.length} operações offline detectadas');
      
      if (_isOnline) {
        print('🌐 Online - processando fila...');
        await syncOfflineQueue();
      } else {
        print('📵 Offline - fila será processada quando conectar');
      }
    } else {
      print('✅ Nenhuma operação offline pendente');
    }
    
    // ✅ CONFIGURAR LISTENERS DEPOIS DA FILA
    _setupConnectivityListener();
    _setupRealtimeListeners();
    
    // ✅ SINCRONIZAÇÃO INICIAL (SE ONLINE E FILA VAZIA)
    if (_isOnline && _offlineQueue.isEmpty) {
      print('🔄 Iniciando sincronização completa...');
      await syncAll();
    } else if (_isOnline && _offlineQueue.isNotEmpty) {
      print('⏭️ Sincronização completa adiada (fila ainda processando)');
    }

    print('✅ Supabase Sync Service inicializado!');
    _updateStatus(SyncStatus.success);
    
  } catch (e) {
    print('❌ Erro ao inicializar: $e');
    print('   Stack trace: ${StackTrace.current}');
    _updateStatus(SyncStatus.error);
    _emitError('Erro na inicialização: $e');
  }
}

  Future<String> _getOrCreateDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  String? deviceId = prefs.getString('device_id');

  if (deviceId == null) {
    // 🔥 SOLUÇÃO: Adicionar componente aleatório
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp * 997) % 999999; // Hash pseudo-aleatório
    deviceId = 'device_${timestamp}_$random';
    await prefs.setString('device_id', deviceId);
    print('🆕 Device ID gerado: $deviceId'); // Log para debug
  } else {
    print('📱 Device ID carregado: $deviceId'); // Log para debug
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
  print('🔧 Configurando listener de conectividade...');
  
  Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
    final wasOffline = !_isOnline;
    _isOnline = results.isNotEmpty && !results.contains(ConnectivityResult.none);

    // ==========================================
    // VOLTOU ONLINE
    // ==========================================
    if (_isOnline && wasOffline) {
      print('🌐 Conexão restaurada! Iniciando sincronização...');
      
      // 🔥 AGUARDAR 2 SEGUNDOS para estabilizar conexão
      await Future.delayed(const Duration(seconds: 2));
      
      // 1️⃣ PROCESSAR FILA OFFLINE PRIMEIRO
      if (_offlineQueue.isNotEmpty) {
        print('📤 Processando ${_offlineQueue.length} operações offline...');
        
        try {
          await syncOfflineQueue();
          print('✅ Fila offline processada');
        } catch (e) {
          print('❌ Erro ao processar fila: $e');
        }
      }
      
      // 2️⃣ SINCRONIZAÇÃO COMPLETA (apenas se fila vazia)
      if (_offlineQueue.isEmpty && _isOnline) {
        print('🔄 Iniciando sincronização completa...');
        
        try {
          await syncAll();
          print('✅ Sincronização completa concluída');
          _updateStatus(SyncStatus.success);
        } catch (e) {
          print('❌ Erro na sync completa: $e');
          _updateStatus(SyncStatus.error);
        }
      } else if (_offlineQueue.isNotEmpty) {
        print('⏭️ Sincronização completa adiada (${_offlineQueue.length} ops pendentes)');
        _updateStatus(SyncStatus.syncing);
        
        // 🔥 RETRY: Tentar novamente após 5 segundos
        Future.delayed(const Duration(seconds: 5), () async {
          if (_offlineQueue.isEmpty && _isOnline) {
            print('🔄 Retentativa de sync completa...');
            try {
              await syncAll();
              _updateStatus(SyncStatus.success);
            } catch (e) {
              print('❌ Erro na retentativa: $e');
              _updateStatus(SyncStatus.error);
            }
          }
        });
      }
    }
    
    // ==========================================
    // FICOU OFFLINE
    // ==========================================
    else if (!_isOnline && wasOffline == false) {
      print('📵 Modo offline ativado');
      _updateStatus(SyncStatus.offline);
    }
  });
  
  print('✅ Listener de conectividade configurado');
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
         'nome_pedido': pedidoMap['nome_pedido'],
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
      // ✅ VALIDAR IMAGENS ANTES DO UPLOAD
      final imagensComUrl = <ProdutoImagem>[];
      
      for (final imagem in imagens) {
        // 🔥 VALIDAÇÃO: Verificar se caminho não é null/vazio
        if (imagem.caminho.isEmpty) {
          print('⚠️ Imagem sem caminho - ignorando');
          continue;
        }
        
        String? caminhoFinal = imagem.caminho;
        
        if (!_storageService.isSupabaseUrl(imagem.caminho)) {
          final urlPublica = await _storageService.uploadImagem(imagem.caminho);
          
          if (urlPublica != null && urlPublica.isNotEmpty) {
            caminhoFinal = urlPublica;
            print('✅ Upload: ${imagem.caminho} → $urlPublica');
          } else {
            print('⚠️ Falha no upload - usando caminho local');
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
  // Upload de imagens
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
  
  // 1. Atualizar localmente PRIMEIRO
  final result = await _localDb.updateProduto(produto, idsCategorias, imagensComUrl);

  // 2. Sincronizar com Supabase
  if (_isOnline && produto.id != null) {
    try {
      await _supabase.from('produtos').update({
        'nome_produto': produto.nome,
        'descricao': produto.descricao,
        'preco': produto.preco,
        'preco_promocional': produto.precoPromocional,
        'quantidade_estoque': produto.quantidadeEstoque,
        'ativo': produto.ativo,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'device_id': _deviceId,
      }).eq('id_produto', produto.id!);
      
      await _supabase.from('produto_categoria').delete().eq('id_produto', produto.id!);
      for (final idCategoria in idsCategorias) {
        await _supabase.from('produto_categoria').insert({
          'id_produto': produto.id!,
          'id_categoria': idCategoria,
        });
      }
      
      await _supabase.from('produto_imagem').delete().eq('id_produto', produto.id!);
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
      // 🔥 ADICIONAR À FILA OFFLINE
      _addToOfflineQueue(OfflineOperation(
        type: 'update_produto',
        data: {
          'produto': produto.toMap(),
          'categorias': idsCategorias,
          'imagens': imagensComUrl.map((i) => i.toMap()).toList(),
        },
        timestamp: DateTime.now(),
      ));
    }
  } else if (!_isOnline) {
    // 🔥 MODO OFFLINE
    _addToOfflineQueue(OfflineOperation(
      type: 'update_produto',
      data: {
        'produto': produto.toMap(),
        'categorias': idsCategorias,
        'imagens': imagensComUrl.map((i) => i.toMap()).toList(),
      },
      timestamp: DateTime.now(),
    ));
  }

  return result;
}

Future<int> deleteProduto(int idProduto) async {
  // 1. Deletar localmente PRIMEIRO
  final result = await _localDb.deleteProduto(idProduto);

  // 2. Sincronizar com Supabase
  if (_isOnline) {
    try {
      await _supabase.from('produtos').delete().eq('id_produto', idProduto);
      print('✅ Produto $idProduto deletado do Supabase');
      
    } catch (e) {
      print('⚠️ Erro ao sincronizar exclusão: $e');
      _addToOfflineQueue(OfflineOperation(
        type: 'delete_produto',
        data: {'id_produto': idProduto},
        timestamp: DateTime.now(),
      ));
    }
  } else {
    _addToOfflineQueue(OfflineOperation(
      type: 'delete_produto',
      data: {'id_produto': idProduto},
      timestamp: DateTime.now(),
    ));
  }

  return result;
}


Future<int> toggleAtivoProduto(int idProduto, bool isActive) async {
  // 1. Atualizar localmente PRIMEIRO
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
      
      // 🔥 ADICIONAR À FILA OFFLINE
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
    // 3. Se OFFLINE, adicionar à fila
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
  if (_isOnline) {
    try {
      final response = await _supabase.from('categorias').insert({
        'nome_categoria': categoria.nome,
        'descricao': categoria.descricao,
        'device_id': _deviceId,
      }).select().single();

      final idSupabase = response['id_categoria'] as int;
      print('✅ Categoria criada no Supabase com ID: $idSupabase');
      
      if (idsProdutos.isNotEmpty) {
        for (final idProduto in idsProdutos) {
          await _supabase.from('produto_categoria').insert({
            'id_produto': idProduto,
            'id_categoria': idSupabase,
          });
        }
      }
      
      final categoriaComId = categoria.copyWith(id: idSupabase);
      await _localDb.createCategoriaComIdEspecifico(categoriaComId, idsProdutos);

      return idSupabase;
      
    } catch (e) {
      print('❌ Erro ao criar categoria no Supabase: $e');
      // 🔥 FALLBACK OFFLINE
      final idLocal = await _localDb.createCategoria(categoria, idsProdutos);
      _addToOfflineQueue(OfflineOperation(
        type: 'create_categoria',
        data: {
          'categoria': categoria.copyWith(id: idLocal).toMap(),
          'produtos': idsProdutos,
        },
        timestamp: DateTime.now(),
      ));
      return idLocal;
    }
  } else {
    // 🔥 MODO OFFLINE
    final idLocal = await _localDb.createCategoria(categoria, idsProdutos);
    _addToOfflineQueue(OfflineOperation(
      type: 'create_categoria',
      data: {
        'categoria': categoria.copyWith(id: idLocal).toMap(),
        'produtos': idsProdutos,
      },
      timestamp: DateTime.now(),
    ));
    return idLocal;
  }
}

// lib/services/supabase_sync_service.dart

Future<int> updateCategoria(Categoria categoria, List<int> idsProdutos) async {
  // 1. Atualizar localmente PRIMEIRO
  final result = await _localDb.updateCategoria(categoria, idsProdutos);

  // 2. Sincronizar com Supabase
  if (_isOnline && categoria.id != null) {
    try {
      await _supabase.from('categorias').update({
        'nome_categoria': categoria.nome,
        'descricao': categoria.descricao,
        'device_id': _deviceId,
      }).eq('id_categoria', categoria.id!);
      
      await _supabase.from('produto_categoria').delete().eq('id_categoria', categoria.id!);
      
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
      _addToOfflineQueue(OfflineOperation(
        type: 'update_categoria',
        data: {
          'categoria': categoria.toMap(),
          'produtos': idsProdutos,
        },
        timestamp: DateTime.now(),
      ));
    }
  } else if (!_isOnline) {
    _addToOfflineQueue(OfflineOperation(
      type: 'update_categoria',
      data: {
        'categoria': categoria.toMap(),
        'produtos': idsProdutos,
      },
      timestamp: DateTime.now(),
    ));
  }

  return result;
}


Future<int> deleteCategoria(int idCategoria) async {
  // 1. Deletar localmente PRIMEIRO
  final result = await _localDb.deleteCategoria(idCategoria);
  
  print('🗑️ Categoria $idCategoria deletada localmente');  // 🔥 LOG DIAGNÓSTICO
  
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
      
    } catch (e) {
      print('❌ Erro ao deletar categoria no Supabase: $e');
      
      // 🔥 ADICIONAR À FILA OFFLINE
      _addToOfflineQueue(OfflineOperation(
        type: 'delete_categoria',
        data: {'id_categoria': idCategoria},
        timestamp: DateTime.now(),
      ));
      
      print('📝 Exclusão de categoria $idCategoria adicionada à fila offline');  // 🔥 LOG DIAGNÓSTICO
    }
  } else {
    // 3. Se OFFLINE, adicionar à fila
    print('📵 Modo offline - adicionando exclusão à fila');  // 🔥 LOG DIAGNÓSTICO
    
    _addToOfflineQueue(OfflineOperation(
      type: 'delete_categoria',
      data: {'id_categoria': idCategoria},
      timestamp: DateTime.now(),
    ));
    
    print('📝 Exclusão de categoria $idCategoria na fila (${_offlineQueue.length} operações pendentes)');  // 🔥 LOG DIAGNÓSTICO
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
  
  // 🔥 Gerar reference ANTES (para verificação posterior)
  final reference = 'PED-${DateTime.now().millisecondsSinceEpoch}-${_deviceId?.substring(0, 8) ?? ""}';
  
  // Teste de conexão
  try {
    await _supabase
      .from('pedidos')
      .select('id_pedido')
      .limit(1)
      .timeout(const Duration(seconds: 2));
    
  } on TimeoutException {
    print('⚠️ Conexão instável - criando offline');
    return await _createPedidoOffline(pedido, itens, reference);
  } catch (e) {
    print('⚠️ Erro no teste de conexão: $e - criando offline');
    return await _createPedidoOffline(pedido, itens, reference);
  }
  
  // ONLINE: Usar RPC
  try {
    final itensJson = itens.map((item) => {
      'id_produto': item.idProduto,
      'quantidade': item.quantidade,
      'preco_unitario': item.precoUnitario,
      'subtotal': item.subtotal,
    }).toList();
    
    print('🔄 Criando pedido no Supabase via RPC (ref: $reference)...');
    if (pedido.nomePedido != null) {
      print('📝 Nome do pedido: "${pedido.nomePedido}"');
    }
    
    final response = await _supabase.rpc('criar_pedido_completo', params: {
      'p_reference': reference,
      'p_id_usuario': pedido.idUsuario,
      'p_idtipo_pagamento': pedido.idTipoPagamento,
      'p_itens': itensJson,
      'p_telefone': pedido.telefone,
      'p_email': pedido.email,
      'p_device_id': _deviceId,
      'p_bairro': pedido.bairro,
      'p_ponto_referencia': pedido.pontoReferencia,
      'p_endereco_json': pedido.enderecoJson,
      'p_nome_pedido': pedido.nomePedido, // 🔥 ADICIONAR ESTE PARÂMETRO
    }).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Timeout ao criar pedido'),
    );
    
    if (response.isEmpty) {
      throw Exception('RPC não retornou dados');
    }
    
    final resultado = response[0];
    final idSupabase = resultado['id_pedido'] as int;
    final total = (resultado['total'] as num).toDouble();
    final itensCriados = resultado['itens_criados'] as int;
    final estoqueDebitado = resultado['estoque_debitado'] as bool;
    
    print('✅ Pedido #$idSupabase criado via RPC');
    print('   Total: MZN $total');
    print('   Itens: $itensCriados');
    print('   Estoque: ${estoqueDebitado ? "Debitado ✓" : "Erro ✗"}');
    
    // 🔥 Criar localmente com try-catch isolado
    try {
      await _criarPedidoLocalAposRPC(pedido, itens, idSupabase, reference, total);
      print('✅ Pedido sincronizado localmente');
    } catch (e) {
      print('⚠️ Erro ao criar localmente (pedido existe no Supabase): $e');
      _addToOfflineQueue(OfflineOperation(
        type: 'sync_pedido_existente',
        data: {'id_pedido': idSupabase, 'reference': reference},
        timestamp: DateTime.now(),
      ));
    }
    
    return idSupabase;
    
  } on TimeoutException catch (e) {
    print('⏱️ Timeout: $e');
    
    // Verificar se pedido foi criado apesar do timeout
    final pedidoExistente = await _verificarPedidoRemoto(reference);
    
    if (pedidoExistente != null) {
      print('✅ Pedido encontrado no Supabase apesar do timeout!');
      final idSupabase = pedidoExistente['id_pedido'] as int;
      final total = (pedidoExistente['total'] as num).toDouble();
      
      try {
        await _criarPedidoLocalAposRPC(pedido, itens, idSupabase, reference, total);
      } catch (e) {
        print('⚠️ Erro ao criar localmente: $e');
        _addToOfflineQueue(OfflineOperation(
          type: 'sync_pedido_existente',
          data: {'id_pedido': idSupabase, 'reference': reference},
          timestamp: DateTime.now(),
        ));
      }
      
      return idSupabase;
    }
    
    // Pedido realmente não foi criado → criar offline
    print('📵 Pedido não encontrado no Supabase - criando offline');
    return await _createPedidoOffline(pedido, itens, reference);
    
  } catch (e) {
    print('❌ Erro ao criar pedido: $e');
    
    // Verificar se é erro de validação
    if (e.toString().contains('Estoque insuficiente') || 
        e.toString().contains('não encontrado') ||
        e.toString().contains('obrigatório')) {
      rethrow;
    }
    
    // Para outros erros, verificar se pedido foi criado
    final pedidoExistente = await _verificarPedidoRemoto(reference);
    
    if (pedidoExistente != null) {
      print('✅ Pedido foi criado no Supabase apesar do erro');
      final idSupabase = pedidoExistente['id_pedido'] as int;
      final total = (pedidoExistente['total'] as num).toDouble();
      
      try {
        await _criarPedidoLocalAposRPC(pedido, itens, idSupabase, reference, total);
      } catch (e) {
        _addToOfflineQueue(OfflineOperation(
          type: 'sync_pedido_existente',
          data: {'id_pedido': idSupabase, 'reference': reference},
          timestamp: DateTime.now(),
        ));
      }
      
      return idSupabase;
    }
    
    // Criar offline
    return await _createPedidoOffline(pedido, itens, reference);
  }
}


// 🔥 NOVO MÉTODO: Verificar se pedido existe no Supabase
Future<Map<String, dynamic>?> _verificarPedidoRemoto(String reference) async {
  try {
    print('🔍 Verificando se pedido $reference existe no Supabase...');
    
    final response = await _supabase
        .from('pedidos')
        .select('id_pedido, total, status_pedido')
        .eq('reference', reference)
        .maybeSingle()
        .timeout(const Duration(seconds: 3));
    
    if (response != null) {
      print('✅ Pedido encontrado: ID ${response['id_pedido']}');
    } else {
      print('❌ Pedido não encontrado');
    }
    
    return response;
    
  } catch (e) {
    print('⚠️ Erro ao verificar pedido remoto: $e');
    return null;
  }
}

// 🔥 NOVO MÉTODO: Criar pedido localmente após RPC bem-sucedido
Future<void> _criarPedidoLocalAposRPC(
  Pedido pedido,
  List<ItemPedido> itens,
  int idSupabase,
  String reference,
  double total,
) async {
  final db = await _localDb.database;
  
  await db.transaction((txn) async {
    final pedidoComId = pedido.copyWith(
      id: idSupabase,
      reference: reference,
      total: total,
      statusPedido: 'por finalizar',
      dataPedido: DateTime.now().toIso8601String(),
      // nomePedido já está em pedido.nomePedido, não precisa passar aqui
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
      
      await txn.rawUpdate(
        'UPDATE produto SET quantidade_estoque = quantidade_estoque - ? WHERE id_produto = ?',
        [item.quantidade, item.idProduto],
      );
    }
  });
}


// 🔥 MODIFICADO: Aceitar reference como parâmetro
Future<int> _createPedidoOffline(
  Pedido pedido, 
  List<ItemPedido> itens,
  [String? reference]
) async {
  print('📵 Modo offline - criando pedido localmente');
  
  try {
    final db = await _localDb.database;
    
    return await db.transaction((txn) async {
      final refFinal = reference ?? 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}';
      
      final pedidoMap = pedido.copyWith(
        reference: refFinal,
        statusPedido: 'por finalizar',
      ).toMap();
      
      pedidoMap['data_pedido'] = DateTime.now().toIso8601String();
      pedidoMap.remove('id_pedido');
      
      final idLocal = await txn.insert('pedido', pedidoMap);
      
      double totalCalculado = 0;
      
      for (final item in itens) {
        final itemMap = item.copyWith(idPedido: idLocal).toMap();
        itemMap.remove('id_item_pedido');
        
        await txn.insert('item_pedido', itemMap);
        
        await txn.rawUpdate(
          'UPDATE produto SET quantidade_estoque = quantidade_estoque - ? WHERE id_produto = ?',
          [item.quantidade, item.idProduto],
        );
        
        totalCalculado += item.subtotal;
      }
      
      await txn.update(
        'pedido',
        {'total': totalCalculado},
        where: 'id_pedido = ?',
        whereArgs: [idLocal],
      );
      
      // 🔥 ADICIONAR À FILA OFFLINE COM NOME_PEDIDO
      _addToOfflineQueue(OfflineOperation(
        type: 'create_pedido_completo',
        data: {
          'id_pedido_local': idLocal,
          'reference': refFinal,
          'pedido': pedidoMap, // 🔥 JÁ CONTÉM nome_pedido
          'itens': itens.map((i) => {
            'id_produto': i.idProduto,
            'quantidade': i.quantidade,
            'preco_unitario': i.precoUnitario,
            'subtotal': i.subtotal,
          }).toList(),
        },
        timestamp: DateTime.now(),
      ));
      
      print('✅ Pedido #$idLocal criado offline (ref: $refFinal)');
      print('   Nome: ${pedido.nomePedido ?? "(sem nome)"}'); // 🔥 LOG DIAGNÓSTICO
      
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
  
  // ==========================================
  // 1. EXECUTAR LOCALMENTE PRIMEIRO (TRANSAÇÃO)
  // ==========================================
  await db.transaction((txn) async {
    // 1.1 Buscar dados do produto
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
    
    // 1.2 Verificar estoque disponível
    if (estoqueDisponivel == null || estoqueDisponivel < quantidade) {
      throw Exception(
        'Estoque insuficiente para $nomeProduto.\n'
        'Disponível: ${estoqueDisponivel ?? 0} | Solicitado: $quantidade'
      );
    }
    
    // 1.3 Verificar se item já existe no pedido
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
      
    } else {
      // 🔥 ITEM NOVO: Inserir
      final subtotal = quantidade * preco;
      
      await txn.insert('item_pedido', {
        'id_pedido': idPedido,
        'id_produto': idProduto,
        'quantidade': quantidade,
        'preco_unitario': preco,
        'subtotal': subtotal,
      });
      
      print('✅ Novo item adicionado: $nomeProduto (x$quantidade)');
    }
    
    // 1.4 🔥 DÉBITO DE ESTOQUE (sempre executado)
    await txn.rawUpdate(
      'UPDATE produto SET quantidade_estoque = quantidade_estoque - ? WHERE id_produto = ?',
      [quantidade, idProduto],
    );
    
    print('📦 Estoque debitado: $nomeProduto (-$quantidade)');
    
    // 1.5 🔥 CRÍTICO: Recalcular total do pedido LOCALMENTE
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
    
    print('💰 Total do pedido recalculado localmente: MZN ${total.toStringAsFixed(2)}');
  }); // 🔥 FIM DA TRANSAÇÃO
  
  // ==========================================
  // 2. SINCRONIZAÇÃO COM SUPABASE (FORA DA TRANSAÇÃO)
  // ==========================================
  
  if (_isOnline) {
    try {
      print('🌐 Sincronizando item adicionado com Supabase...');
      
      // 2.1 Verificar se item já existe no Supabase
      final itemSupabaseResponse = await _supabase
          .from('itens_pedido')
          .select('id_item_pedido, quantidade, preco_unitario')
          .eq('id_pedido', idPedido)
          .eq('id_produto', idProduto);
      
      if (itemSupabaseResponse.isNotEmpty) {
        // 🔥 ITEM JÁ EXISTE NO SUPABASE: Atualizar quantidade
        final itemRemoto = itemSupabaseResponse.first;
        final idItemRemoto = itemRemoto['id_item_pedido'] as int;
        final quantidadeRemota = itemRemoto['quantidade'] as int;
        final precoUnitario = (itemRemoto['preco_unitario'] as num).toDouble();
        
        final novaQuantidadeRemota = quantidadeRemota + quantidade;
        final novoSubtotalRemoto = novaQuantidadeRemota * precoUnitario;
        
        await _supabase.from('itens_pedido').update({
          'quantidade': novaQuantidadeRemota,
          'subtotal': novoSubtotalRemoto,
        }).eq('id_item_pedido', idItemRemoto);
        
        print('✅ Item atualizado no Supabase: quantidade ${quantidadeRemota} → $novaQuantidadeRemota');
        
      } else {
        // 🔥 ITEM NOVO NO SUPABASE: Inserir
        final itemLocal = await db.query(
          'item_pedido',
          where: 'id_pedido = ? AND id_produto = ?',
          whereArgs: [idPedido, idProduto],
          limit: 1,
        );
        
        if (itemLocal.isNotEmpty) {
          final item = itemLocal.first;
          
          await _supabase.from('itens_pedido').insert({
            'id_pedido': idPedido,
            'id_produto': idProduto,
            'quantidade': item['quantidade'],
            'preco_unitario': item['preco_unitario'],
            'subtotal': item['subtotal'],
          });
          
          print('✅ Novo item inserido no Supabase');
        }
      }
      
      // 2.2 Debitar estoque no Supabase
      await _supabase.rpc('decrement_stock', params: {
        'product_id': idProduto,
        'quantity': quantidade,
      });
      
      print('✅ Estoque debitado no Supabase: produto $idProduto (-$quantidade)');
      
      // 2.3 Buscar total atualizado do banco local e sincronizar
      final pedidoAtualizado = await db.query(
        'pedido',
        columns: ['total'],
        where: 'id_pedido = ?',
        whereArgs: [idPedido],
      );
      
      if (pedidoAtualizado.isNotEmpty) {
        final totalAtualizado = (pedidoAtualizado.first['total'] as num).toDouble();
        
        await _supabase.from('pedidos').update({
          'total': totalAtualizado,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'device_id': _deviceId,
        }).eq('id_pedido', idPedido);
        
        print('✅ Total do pedido sincronizado com Supabase: MZN ${totalAtualizado.toStringAsFixed(2)}');
      }
      
      print('✅ Sincronização completa com Supabase concluída!');
      
    } catch (e) {
      print('⚠️ Erro ao sincronizar com Supabase: $e');
      
      // 🔥 ADICIONAR À FILA OFFLINE para sincronizar depois
      _addToOfflineQueue(OfflineOperation(
        type: 'adicionar_item_pedido',
        data: {
          'id_pedido': idPedido,
          'id_produto': idProduto,
          'quantidade': quantidade,
        },
        timestamp: DateTime.now(),
      ));
      
      print('📝 Operação adicionada à fila offline');
    }
  } else {
    // 3. 🔥 MODO OFFLINE: Adicionar à fila
    print('📵 Modo offline - adicionando à fila de sincronização');
    
    _addToOfflineQueue(OfflineOperation(
      type: 'adicionar_item_pedido',
      data: {
        'id_pedido': idPedido,
        'id_produto': idProduto,
        'quantidade': quantidade,
      },
      timestamp: DateTime.now(),
    ));
  }
  
  // 🔥 NOTIFICAR MUDANÇAS DE ESTOQUE
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
  
  // Buscar item antes da transação para usar nos dados offline
  final itemMapsPreTransacao = await db.query(
    'item_pedido',
    where: 'id_item_pedido = ?',
    whereArgs: [idItemPedido],
  );
  
  if (itemMapsPreTransacao.isEmpty) {
    throw Exception('Item não encontrado');
  }
  
  final itemParaDadosOffline = ItemPedido.fromMap(itemMapsPreTransacao.first);
  final diferencaQuantidadeParaOffline = novaQuantidade - itemParaDadosOffline.quantidade;
  
  await db.transaction((txn) async {
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
    
    if (diferencaQuantidade != 0) {
      await txn.rawUpdate(
        'UPDATE produto SET quantidade_estoque = quantidade_estoque - ? WHERE id_produto = ?',
        [diferencaQuantidade, itemAtual.idProduto],
      );
      
      print('📦 Estoque ajustado: produto ${itemAtual.idProduto} (diff: $diferencaQuantidade)');
    }
    
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
  });
  
  // 🔥 SINCRONIZAÇÃO FORA DA TRANSAÇÃO
  if (_isOnline) {
    try {
      final itemMapsForSync = await db.query(
        'item_pedido',
        where: 'id_item_pedido = ?',
        whereArgs: [idItemPedido],
      );
      
      if (itemMapsForSync.isNotEmpty) {
        final itemParaSync = ItemPedido.fromMap(itemMapsForSync.first);
        
        await _supabase.from('itens_pedido').update({
          'quantidade': itemParaSync.quantidade,
          'subtotal': itemParaSync.subtotal,
        }).eq('id_item_pedido', idItemPedido);
        
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
            'device_id': _deviceId,
          }).eq('id_produto', itemParaSync.idProduto);
        }
        
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
            'device_id': _deviceId,
          }).eq('id_pedido', itemParaSync.idPedido);
          
          print('✅ Item, estoque e total sincronizados com Supabase');
        }
      }
    } catch (e) {
      print('⚠️ Erro ao sincronizar: $e');
      // 🔥 ADICIONAR À FILA OFFLINE
      _addToOfflineQueue(OfflineOperation(
        type: 'update_quantidade_item',
        data: {
          'id_item_pedido': idItemPedido,
          'nova_quantidade': novaQuantidade,
          'id_produto': itemParaDadosOffline.idProduto,
          'diferenca_quantidade': diferencaQuantidadeParaOffline,
        },
        timestamp: DateTime.now(),
      ));
    }
  } else {
    // 🔥 MODO OFFLINE
    _addToOfflineQueue(OfflineOperation(
      type: 'update_quantidade_item',
      data: {
        'id_item_pedido': idItemPedido,
        'nova_quantidade': novaQuantidade,
        'id_produto': itemParaDadosOffline.idProduto,
        'diferenca_quantidade': diferencaQuantidadeParaOffline,
      },
      timestamp: DateTime.now(),
    ));
  }
  
  notificarMudancaEstoque();
}




// Localização: sync_service.dart, linha ~600
// SUBSTITUIR método completo:

// 🔥 SUBSTITUIR o método completo:
Future<void> cancelarPedido(int idPedido, String motivo, int idUsuarioCancelou) async {
  // 1. Cancelar localmente PRIMEIRO
  await _localDb.cancelarPedido(idPedido, motivo, idUsuarioCancelou);
  
  // 2. Sincronizar com Supabase
  if (_isOnline) {
    try {
      final itensResponse = await _supabase
          .from('itens_pedido')
          .select('id_produto, quantidade')
          .eq('id_pedido', idPedido);
      
      for (final item in itensResponse) {
        await _supabase.rpc('increment_stock', params: {
          'product_id': item['id_produto'],
          'quantity': item['quantidade'],
        });
      }
      
      await _supabase.from('pedidos').update({
        'status_pedido': 'cancelado',
        'data_finalizacao': DateTime.now().toUtc().toIso8601String(),
        'device_id': _deviceId,
      }).eq('id_pedido', idPedido);
      
      print('✅ Pedido $idPedido cancelado no Supabase');
      
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
  } else {
    // 🔥 MODO OFFLINE
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



// 🔥 MESMO ARQUIVO, linha ~680:
Future<void> finalizarPedido(
  int idPedido,
  int idTipoPagamento, {
  double? valorPago,
  double? troco,
}) async {
  // 1. Finalizar localmente PRIMEIRO
  await _localDb.finalizarPedido(
    idPedido,
    idTipoPagamento,
    valorPago: valorPago,
    troco: troco,
  );
  
  // 2. Sincronizar com Supabase
  if (_isOnline) {
    try {
      await _supabase.from('pedidos').update({
        'status_pedido': 'finalizado',
        'idtipo_pagamento': idTipoPagamento,
        'valor_pago_manual': valorPago,
        'troco': troco,
        'data_finalizacao': DateTime.now().toUtc().toIso8601String(),
        'device_id': _deviceId,
      }).eq('id_pedido', idPedido);
      
      print('✅ Pedido $idPedido finalizado no Supabase');
      
    } catch (e) {
      print('⚠️ Erro ao finalizar no Supabase: $e');
      _addToOfflineQueue(OfflineOperation(
        type: 'finalizar_pedido',
        data: {
          'id_pedido': idPedido,
          'idtipo_pagamento': idTipoPagamento,
          'valor_pago_manual': valorPago,
          'troco': troco,
        },
        timestamp: DateTime.now(),
      ));
    }
  } else {
    // 🔥 MODO OFFLINE
    _addToOfflineQueue(OfflineOperation(
      type: 'finalizar_pedido',
      data: {
        'id_pedido': idPedido,
        'idtipo_pagamento': idTipoPagamento,
        'valor_pago_manual': valorPago,
        'troco': troco,
      },
      timestamp: DateTime.now(),
    ));
  }
} // ==========================================
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
  // // 🔥 GARANTIR SINCRONIZAÇÃO ANTES DE LER
  // if (_isOnline) {
  //   await _syncPedidos();
  // }
  
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
  try {
    // ✅ VALIDAR dados antes de adicionar
    if (operation.data.isEmpty) {
      print('⚠️ Operação sem dados - não adicionada à fila');
      return;
    }
    
    _offlineQueue.add(operation);
    _saveOfflineQueue();
    print('📝 Operação adicionada à fila offline: ${operation.type}');
  } catch (e) {
    print('❌ Erro ao adicionar operação à fila: $e');
  }
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

  
Future<void> validarFilaOffline() async {
  print('🔍 Validando fila offline...');
  
  int removidos = 0;
  _offlineQueue.removeWhere((op) {
    if (op.type == 'create_produto') {
      final imagensData = op.data['imagens'] as List<dynamic>?;
      if (imagensData != null) {
        for (final img in imagensData) {
          if (img is Map && img['caminho'] == null) {
            print('🗑️ Removendo operação com imagem inválida');
            removidos++;
            return true;
          }
        }
      }
    }
    return false;
  });
  
  if (removidos > 0) {
    await _saveOfflineQueue();
    print('✅ $removidos operações inválidas removidas da fila');
  } else {
    print('✅ Fila offline válida');
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
  try {
    final produtoData = operation.data['produto'] as Map<String, dynamic>;
    final produto = Produto.fromMap(produtoData);
    final idsCategorias = (operation.data['categorias'] as List<dynamic>?)?.cast<int>() ?? [];
    final imagensData = (operation.data['imagens'] as List<dynamic>?) ?? [];
    
    print('📤 Processando produto offline: ${produto.nome}');
    
    // ✅ CORREÇÃO: Validar e fazer upload das imagens
    final imagensComUrl = <Map<String, dynamic>>[];
    
    for (final imgData in imagensData) {
      if (imgData == null || imgData is! Map<String, dynamic>) {
        print('⚠️ Imagem inválida ignorada');
        continue;
      }
      
      // 🔥 VALIDAÇÃO: Verificar se caminho existe e não é null
      final caminhoLocal = imgData['caminho'] as String?;
      if (caminhoLocal == null || caminhoLocal.isEmpty) {
        print('⚠️ Caminho de imagem vazio - ignorando');
        continue;
      }
      
      String caminhoFinal = caminhoLocal;
      
      // Upload apenas se for caminho local
      if (!_storageService.isSupabaseUrl(caminhoLocal)) {
        try {
          final urlPublica = await _storageService.uploadImagem(caminhoLocal);
          if (urlPublica != null && urlPublica.isNotEmpty) {
            caminhoFinal = urlPublica;
            print('✅ Upload offline: ${caminhoLocal.split('/').last} → $urlPublica');
          } else {
            print('⚠️ Upload falhou para $caminhoLocal - usando caminho local');
          }
        } catch (e) {
          print('⚠️ Erro no upload de $caminhoLocal: $e');
          // Mantém caminho local em caso de erro
        }
      }
      
      imagensComUrl.add({
        'caminho': caminhoFinal,
        'legenda': imgData['legenda'] as String?,
        'imagem_principal': imgData['imagem_principal'] ?? 0,
      });
    }
    
    print('📸 ${imagensComUrl.length} imagens processadas');
    
    // Inserir produto no Supabase
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
    
    // Inserir categorias
    if (idsCategorias.isNotEmpty) {
      for (final idCategoria in idsCategorias) {
        await _supabase.from('produto_categoria').insert({
          'id_produto': idSupabase,
          'id_categoria': idCategoria,
        });
      }
      print('✅ ${idsCategorias.length} categorias associadas');
    }
    
    // Inserir imagens COM URLs VALIDADAS
    if (imagensComUrl.isNotEmpty) {
      for (final imagem in imagensComUrl) {
        await _supabase.from('produto_imagem').insert({
          'id_produto': idSupabase,
          'caminho_imagem': imagem['caminho'],
          'legenda': imagem['legenda'],
          'imagem_principal': imagem['imagem_principal'],
        });
      }
      print('✅ ${imagensComUrl.length} imagens inseridas no Supabase');
    }
    
    // Atualizar ID local para ID do Supabase
    final db = await _localDb.database;
    await db.update(
      'produto',
      {'id_produto': idSupabase},
      where: 'id_produto = ?',
      whereArgs: [produto.id],
    );
    
    print('✅ Produto offline sincronizado: ID local ${produto.id} → Supabase $idSupabase');
    
  } catch (e) {
    print('❌ ERRO CRÍTICO ao processar create_produto: $e');
    print('   Stack trace: ${StackTrace.current}');
    rethrow; // Mantém na fila para próxima tentativa
  }
  break;

    case 'update_produto':
  try {
    final produtoData = operation.data['produto'] as Map<String, dynamic>;
    final produto = Produto.fromMap(produtoData);
    final idsCategorias = (operation.data['categorias'] as List<dynamic>?)?.cast<int>() ?? [];
    final imagensData = (operation.data['imagens'] as List<dynamic>?) ?? [];
    
    print('📤 Processando atualização offline: ${produto.nome}');
    
    if (produto.id == null) {
      throw Exception('ID do produto é obrigatório para atualização');
    }
    
    // Upload de imagens se necessário
    final imagensComUrl = <Map<String, dynamic>>[];
    for (final imgData in imagensData) {
      if (imgData == null || imgData is! Map<String, dynamic>) continue;
      
      final caminhoLocal = imgData['caminho'] as String?;
      if (caminhoLocal == null || caminhoLocal.isEmpty) continue;
      
      String caminhoFinal = caminhoLocal;
      if (!_storageService.isSupabaseUrl(caminhoLocal)) {
        final urlPublica = await _storageService.uploadImagem(caminhoLocal);
        if (urlPublica != null) caminhoFinal = urlPublica;
      }
      
      imagensComUrl.add({
        'caminho': caminhoFinal,
        'legenda': imgData['legenda'],
        'imagem_principal': imgData['imagem_principal'] ?? 0,
      });
    }
    
    // Atualizar produto
    await _supabase.from('produtos').update({
      'nome_produto': produto.nome,
      'descricao': produto.descricao,
      'preco': produto.preco,
      'preco_promocional': produto.precoPromocional,
      'quantidade_estoque': produto.quantidadeEstoque,
      'ativo': produto.ativo,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'device_id': _deviceId,
    }).eq('id_produto', produto.id!);
    
    // Atualizar categorias
    await _supabase.from('produto_categoria').delete().eq('id_produto', produto.id!);
    for (final idCategoria in idsCategorias) {
      await _supabase.from('produto_categoria').insert({
        'id_produto': produto.id!,
        'id_categoria': idCategoria,
      });
    }
    
    // Atualizar imagens
    await _supabase.from('produto_imagem').delete().eq('id_produto', produto.id!);
    for (final imagem in imagensComUrl) {
      await _supabase.from('produto_imagem').insert({
        'id_produto': produto.id!,
        'caminho_imagem': imagem['caminho'],
        'legenda': imagem['legenda'],
        'imagem_principal': imagem['imagem_principal'],
      });
    }
    
    print('✅ Produto ${produto.id} atualizado no Supabase');
    
  } catch (e) {
    print('❌ Erro ao processar update_produto: $e');
    rethrow;
  }
  break;

  // case 'delete_produto':
  // try {
  //   final idProduto = operation.data['id_produto'] as int;
    
  //   print('📤 Processando exclusão offline: produto $idProduto');
    
  //   await _supabase.from('produtos').delete().eq('id_produto', idProduto);
    
  //   print('✅ Produto $idProduto deletado do Supabase');
    
  // } catch (e) {
  //   print('❌ Erro ao processar delete_produto: $e');
  //   rethrow;
  // }
  // break;



        // ==========================================
// lib/services/supabase_sync_service.dart
// MÉTODO: _processOfflineOperation (linha ~740)
// ADICIONE ESTES CASES NO SWITCH:
// ==========================================

case 'create_usuario':
  try {
    final usuarioData = operation.data['usuario'] as Map<String, dynamic>;
    final usuario = Usuario.fromMap(usuarioData);
    
    print('📤 Processando usuário offline: ${usuario.nome}');
    
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
    
    final db = await _localDb.database;
    await db.update(
      'usuario',
      {'id_usuario': idSupabase},
      where: 'id_usuario = ?',
      whereArgs: [usuario.id],
    );
    
    print('✅ Usuário offline sincronizado: ID local ${usuario.id} → Supabase $idSupabase');
    
  } catch (e) {
    print('❌ Erro ao processar create_usuario: $e');
    rethrow;
  }
  break;

case 'update_usuario':
  try {
    final usuarioData = operation.data['usuario'] as Map<String, dynamic>;
    final usuario = Usuario.fromMap(usuarioData);
    
    print('📤 Processando atualização offline: usuário ${usuario.nome}');
    
    if (usuario.id == null) {
      throw Exception('ID do usuário é obrigatório');
    }
    
    await _supabase.from('usuario').update({
      'nome': usuario.nome,
      'apelido': usuario.apelido,
      'email': usuario.email,
      'senha_hash': usuario.senhaHash,
      'telefone': usuario.telefone,
      'idperfil': usuario.idPerfil,
      'primeira_senha': usuario.primeiraSenha,
      'ativo': usuario.ativo,
    }).eq('id_usuario', usuario.id!);
    
    print('✅ Usuário ${usuario.id} atualizado no Supabase');
    
  } catch (e) {
    print('❌ Erro ao processar update_usuario: $e');
    rethrow;
  }
  break;
case 'delete_usuario':
  try {
    final idUsuario = operation.data['id_usuario'] as int;
    
    print('📤 Processando exclusão usuário offline: $idUsuario');
    
    await _supabase
        .from('usuario')
        .delete()
        .eq('id_usuario', idUsuario);
    
    print('✅ Usuário deletado do Supabase');
    
  } catch (e) {
    print('❌ Erro ao processar delete_usuario: $e');
    rethrow;
  }
  break;
// ==========================================
// ADICIONAR CASES DE CATEGORIA
// ==========================================

case 'create_categoria':
  try {
    final categoriaData = operation.data['categoria'] as Map<String, dynamic>;
    final categoria = Categoria.fromMap(categoriaData);
    final idsProdutos = (operation.data['produtos'] as List<dynamic>?)?.cast<int>() ?? [];
    
    print('📤 Processando categoria offline: ${categoria.nome}');
    
    final response = await _supabase.from('categorias').insert({
      'nome_categoria': categoria.nome,
      'descricao': categoria.descricao,
      'device_id': _deviceId,
    }).select().single();
    
    final idSupabase = response['id_categoria'] as int;
    
    if (idsProdutos.isNotEmpty) {
      for (final idProduto in idsProdutos) {
        await _supabase.from('produto_categoria').insert({
          'id_produto': idProduto,
          'id_categoria': idSupabase,
        });
      }
    }
    
    // Atualizar ID local
    final db = await _localDb.database;
    await db.update(
      'categoria',
      {'id_categoria': idSupabase},
      where: 'id_categoria = ?',
      whereArgs: [categoria.id],
    );
    
    print('✅ Categoria offline sincronizada: ID local ${categoria.id} → Supabase $idSupabase');
    
  } catch (e) {
    print('❌ Erro ao processar create_categoria: $e');
    rethrow;
  }
  break;

case 'update_categoria':
  try {
    final categoriaData = operation.data['categoria'] as Map<String, dynamic>;
    final categoria = Categoria.fromMap(categoriaData);
    final idsProdutos = (operation.data['produtos'] as List<dynamic>?)?.cast<int>() ?? [];
    
    print('📤 Processando atualização offline: categoria ${categoria.nome}');
    
    if (categoria.id == null) {
      throw Exception('ID da categoria é obrigatório');
    }
    
    await _supabase.from('categorias').update({
      'nome_categoria': categoria.nome,
      'descricao': categoria.descricao,
      'device_id': _deviceId,
    }).eq('id_categoria', categoria.id!);
    
    await _supabase.from('produto_categoria').delete().eq('id_categoria', categoria.id!);
    
    for (final idProduto in idsProdutos) {
      await _supabase.from('produto_categoria').insert({
        'id_produto': idProduto,
        'id_categoria': categoria.id!,
      });
    }
    
    print('✅ Categoria ${categoria.id} atualizada no Supabase');
    
  } catch (e) {
    print('❌ Erro ao processar update_categoria: $e');
    rethrow;
  }
  break;

case 'delete_categoria':
  try {
    final idCategoria = operation.data['id_categoria'] as int;
    
    print('📤 Processando exclusão categoria offline: $idCategoria');
    
    // 🔥 VALIDAR SE A CATEGORIA AINDA EXISTE NO SUPABASE
    final categoriaExiste = await _supabase
        .from('categorias')
        .select('id_categoria')
        .eq('id_categoria', idCategoria)
        .maybeSingle();  // 🔥 USA maybeSingle() para não lançar erro se não existir
    
    if (categoriaExiste == null) {
      print('⚠️ Categoria $idCategoria já foi deletada no Supabase - removendo da fila');
      return;  // 🔥 NÃO faz rethrow, considera como sucesso
    }
    
    // Deletar associações primeiro
    final associacoesResponse = await _supabase
        .from('produto_categoria')
        .delete()
        .eq('id_categoria', idCategoria)
        .select();  // 🔥 ADICIONAR select() para confirmar execução
    
    print('🔗 ${associacoesResponse.length} associações removidas');
    
    // Depois deletar a categoria
    await _supabase
        .from('categorias')
        .delete()
        .eq('id_categoria', idCategoria);
    
    print('✅ Categoria $idCategoria deletada do Supabase com sucesso');
    
  } catch (e) {
    print('❌ Erro ao processar delete_categoria: $e');
    print('   Stack trace: ${StackTrace.current}');  // 🔥 LOG DETALHADO
    rethrow;
  }
  break;


case 'cancelar_pedido':
  try {
    final idPedido = operation.data['id_pedido'] as int;
    final motivo = operation.data['motivo'] as String;
    final idUsuario = operation.data['id_usuario_cancelou'] as int;
    
    print('📤 Processando cancelamento offline: pedido $idPedido');
    
    final itensResponse = await _supabase
        .from('itens_pedido')
        .select('id_produto, quantidade')
        .eq('id_pedido', idPedido);
    
    for (final item in itensResponse) {
      await _supabase.rpc('increment_stock', params: {
        'product_id': item['id_produto'],
        'quantity': item['quantidade'],
      });
    }
    
    await _supabase.from('pedidos').update({
      'status_pedido': 'cancelado',
      'data_finalizacao': DateTime.now().toUtc().toIso8601String(),
      'device_id': _deviceId,
    }).eq('id_pedido', idPedido);
    
    print('✅ Pedido $idPedido cancelado no Supabase');
    
  } catch (e) {
    print('❌ Erro ao processar cancelar_pedido: $e');
    rethrow;
  }
  break;

case 'finalizar_pedido':
  try {
    final idPedido = operation.data['id_pedido'] as int;
    final idTipoPagamento = operation.data['idtipo_pagamento'] as int;
    final valorPago = operation.data['valor_pago_manual'] as double?;
    final troco = operation.data['troco'] as double?;
    
    print('📤 Processando finalização offline: pedido $idPedido');
    
    await _supabase.from('pedidos').update({
      'status_pedido': 'finalizado',
      'idtipo_pagamento': idTipoPagamento,
      'valor_pago_manual': valorPago,
      'troco': troco,
      'data_finalizacao': DateTime.now().toUtc().toIso8601String(),
      'device_id': _deviceId,
    }).eq('id_pedido', idPedido);
    
    print('✅ Pedido $idPedido finalizado no Supabase');
    
  } catch (e) {
    print('❌ Erro ao processar finalizar_pedido: $e');
    rethrow;
  }
  break;

case 'toggle_ativo_produto':
  try {
    final idProduto = operation.data['id_produto'] as int;
    final ativo = operation.data['ativo'] as int;
    
    print('📤 Processando toggle produto offline: $idProduto');
    
    await _supabase
        .from('produtos')
        .update({
          'ativo': ativo,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'device_id': _deviceId,
        })
        .eq('id_produto', idProduto);
    
    print('✅ Status do produto sincronizado');
    
  } catch (e) {
    print('❌ Erro ao processar toggle_ativo_produto: $e');
    rethrow;
  }
  break;


case 'update_quantidade_item':
  try {
    final idItemPedido = operation.data['id_item_pedido'] as int;
    final novaQuantidade = operation.data['nova_quantidade'] as int;
    final idProduto = operation.data['id_produto'] as int;
    final diferencaQuantidade = operation.data['diferenca_quantidade'] as int;
    
    print('📤 Processando atualização de quantidade offline');
    
    // 1. Buscar item atual e obter id_pedido
    final itemResponse = await _supabase
        .from('itens_pedido')
        .select('preco_unitario, id_pedido')  // 🔥 ADICIONAR id_pedido
        .eq('id_item_pedido', idItemPedido)
        .single();
    
    final precoUnitario = (itemResponse['preco_unitario'] as num).toDouble();
    final idPedido = itemResponse['id_pedido'] as int;  // 🔥 EXTRAIR id_pedido
    final novoSubtotal = novaQuantidade * precoUnitario;
    
    // 2. Atualizar item
    await _supabase.from('itens_pedido').update({
      'quantidade': novaQuantidade,
      'subtotal': novoSubtotal,
    }).eq('id_item_pedido', idItemPedido);
    
    // 3. Ajustar estoque pela diferença
    if (diferencaQuantidade > 0) {
      await _supabase.rpc('decrement_stock', params: {
        'product_id': idProduto,
        'quantity': diferencaQuantidade,
      });
    } else if (diferencaQuantidade < 0) {
      await _supabase.rpc('increment_stock', params: {
        'product_id': idProduto,
        'quantity': -diferencaQuantidade,
      });
    }
    
    // 4. 🔥 CRÍTICO: RECALCULAR TOTAL DO PEDIDO (ESTAVA FALTANDO)
    final itensResponse = await _supabase
        .from('itens_pedido')
        .select('subtotal')
        .eq('id_pedido', idPedido);
    
    final totalCalculado = itensResponse.fold<double>(
      0.0,
      (sum, item) => sum + ((item['subtotal'] as num).toDouble()),
    );
    
    await _supabase.from('pedidos').update({
      'total': totalCalculado,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'device_id': _deviceId,
    }).eq('id_pedido', idPedido);
    
    print('💰 Total do pedido recalculado no Supabase: MZN ${totalCalculado.toStringAsFixed(2)}');
    print('✅ Quantidade atualizada no Supabase');
    
  } catch (e) {
    print('❌ Erro ao processar update_quantidade_item: $e');
    rethrow;
  }
  break;

  // 🔥 ADICIONAR ESTE CASE no switch de _processOfflineOperation:

case 'create_pedido_completo':
  try {
    final pedidoData = operation.data['pedido'] as Map<String, dynamic>;
    final itensData = operation.data['itens'] as List<dynamic>;
    final idPedidoLocal = operation.data['id_pedido_local'] as int;
    final reference = operation.data['reference'] as String;
    
    print('🔄 Sincronizando pedido offline (ref: $reference)...');
    
    // Verificar se pedido já existe no Supabase
    final pedidoExistente = await _supabase
        .from('pedidos')
        .select('id_pedido, total')
        .eq('reference', reference)
        .maybeSingle();
    
    if (pedidoExistente != null) {
      final idSupabase = pedidoExistente['id_pedido'] as int;
      
      print('✅ Pedido já existe no Supabase (ID: $idSupabase)');
      
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
      
      print('✅ IDs locais atualizados para ID Supabase $idSupabase');
      return;
    }
    
    // 🔥 PEDIDO NÃO EXISTE: Usar RPC COM NOME_PEDIDO
    final itensJson = itensData.map((item) => {
      'id_produto': item['id_produto'],
      'quantidade': item['quantidade'],
      'preco_unitario': item['preco_unitario'],
      'subtotal': item['subtotal'],
    }).toList();
    
    final response = await _supabase.rpc('criar_pedido_completo', params: {
      'p_reference': reference,
      'p_id_usuario': pedidoData['id_usuario'],
      'p_idtipo_pagamento': pedidoData['idtipo_pagamento'],
      'p_itens': itensJson,
      'p_telefone': pedidoData['telefone'],
      'p_email': pedidoData['email'],
      'p_device_id': _deviceId,
      'p_bairro': pedidoData['bairro'],
      'p_ponto_referencia': pedidoData['ponto_referencia'],
      'p_endereco_json': pedidoData['endereco_json'],
      'p_nome_pedido': pedidoData['nome_pedido'], // 🔥 ADICIONAR AQUI
    });
    
    if (response.isEmpty) {
      throw Exception('RPC não retornou dados');
    }
    
    final idSupabase = response[0]['id_pedido'] as int;
    
    // Atualizar IDs locais
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
    rethrow;
  }
  break;
  

case 'sync_pedido_existente':
  try {
    final idPedido = operation.data['id_pedido'] as int;
    final reference = operation.data['reference'] as String;
    
    print('🔄 Sincronizando pedido existente $idPedido...');
    
    // Buscar pedido completo do Supabase
    final pedidoResponse = await _supabase
        .from('pedidos')
        .select('*')
        .eq('id_pedido', idPedido)
        .single();
    
    final itensResponse = await _supabase
        .from('itens_pedido')
        .select('*')
        .eq('id_pedido', idPedido);
    
    // Criar/atualizar localmente
    final db = await _localDb.database;
    await db.insert(
      'pedido',
      pedidoResponse,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    for (final itemData in itensResponse) {
      await db.insert(
        'item_pedido',
        itemData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    print('✅ Pedido $idPedido sincronizado localmente');
    
  } catch (e) {
    print('❌ Erro ao sincronizar pedido existente: $e');
    rethrow;
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

case 'toggle_ativo_usuario':
  try {
    final idUsuario = operation.data['id_usuario'] as int;
    final ativo = operation.data['ativo'] as int;
    
    print('📤 Processando toggle ativo offline: usuário $idUsuario');
    
    await _supabase.from('usuario').update({
      'ativo': ativo,
    }).eq('id_usuario', idUsuario);
    
    print('✅ Status do usuário atualizado no Supabase');
    
  } catch (e) {
    print('❌ Erro ao processar toggle_ativo_usuario: $e');
    rethrow;
  }
  break;

case 'adicionar_item_pedido':
  try {
    final idPedido = operation.data['id_pedido'] as int;
    final idProduto = operation.data['id_produto'] as int;
    final quantidade = operation.data['quantidade'] as int;
    
    print('🔄 Processando item offline: pedido $idPedido, produto $idProduto');
    
    // 1. Buscar preço do produto
    final produtoResponse = await _supabase
        .from('produtos')
        .select('preco')
        .eq('id_produto', idProduto)
        .single();
    
    final preco = (produtoResponse['preco'] as num).toDouble();
    
    // 2. 🔥 CRÍTICO: Verificar se item já existe no Supabase
    final itemExistenteResponse = await _supabase
        .from('itens_pedido')
        .select('id_item_pedido, quantidade')
        .eq('id_pedido', idPedido)
        .eq('id_produto', idProduto);
    
    if (itemExistenteResponse.isNotEmpty) {
      // 🔥 ITEM JÁ EXISTE NO SUPABASE: Atualizar quantidade
      final itemRemoto = itemExistenteResponse.first;
      final idItemRemoto = itemRemoto['id_item_pedido'] as int;
      final quantidadeRemota = itemRemoto['quantidade'] as int;
      
      final novaQuantidade = quantidadeRemota + quantidade;
      final novoSubtotal = novaQuantidade * preco;
      
      await _supabase.from('itens_pedido').update({
        'quantidade': novaQuantidade,
        'subtotal': novoSubtotal,
      }).eq('id_item_pedido', idItemRemoto);
      
      print('✅ Item existente atualizado no Supabase: ${quantidadeRemota} → $novaQuantidade');
      
    } else {
      // 🔥 ITEM NOVO NO SUPABASE: Inserir
      await _supabase.from('itens_pedido').insert({
        'id_pedido': idPedido,
        'id_produto': idProduto,
        'quantidade': quantidade,
        'preco_unitario': preco,
        'subtotal': quantidade * preco,
      });
      
      print('✅ Novo item inserido no Supabase');
    }
    
    // 3. Debitar estoque
    await _supabase.rpc('decrement_stock', params: {
      'product_id': idProduto,
      'quantity': quantidade,
    });
    
    print('✅ Estoque debitado no Supabase: produto $idProduto (-$quantidade)');
    
    // 4. 🔥 CRÍTICO: Recalcular total do pedido no Supabase
    final itensResponse = await _supabase
        .from('itens_pedido')
        .select('subtotal')
        .eq('id_pedido', idPedido);
    
    final totalCalculado = itensResponse.fold<double>(
      0.0,
      (sum, item) => sum + ((item['subtotal'] as num).toDouble()),
    );
    
    await _supabase.from('pedidos').update({
      'total': totalCalculado,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'device_id': _deviceId,
    }).eq('id_pedido', idPedido);
    
    print('💰 Total do pedido recalculado no Supabase: MZN ${totalCalculado.toStringAsFixed(2)}');
    print('✅ Item offline processado com sucesso');
    
  } catch (e) {
    print('❌ Erro ao processar item offline: $e');
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
  _movimentosChannel?.unsubscribe(); // 🔥 ADICIONAR
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
      
      final usuarioComId = usuario.copyWith(id: idSupabase);
      final db = await _localDb.database;
      await db.insert('usuario', usuarioComId.toMap());

      return usuarioComId;
      
    } catch (e) {
      print('❌ Erro ao criar usuário no Supabase: $e');
      // 🔥 FALLBACK OFFLINE
      final usuarioLocal = await _localDb.createUsuario(usuario);
      _addToOfflineQueue(OfflineOperation(
        type: 'create_usuario',
        data: {'usuario': usuarioLocal.toMap()},
        timestamp: DateTime.now(),
      ));
      return usuarioLocal;
    }
  } else {
    // 🔥 MODO OFFLINE
    final usuarioLocal = await _localDb.createUsuario(usuario);
    _addToOfflineQueue(OfflineOperation(
      type: 'create_usuario',
      data: {'usuario': usuarioLocal.toMap()},
      timestamp: DateTime.now(),
    ));
    return usuarioLocal;
  }
}


Future<int> updateUsuario(Usuario usuario) async {
  // 1. Atualizar localmente PRIMEIRO
  final result = await _localDb.updateUsuario(usuario);
  
  // 2. Sincronizar com Supabase
  if (_isOnline && usuario.id != null) {
    try {
      await _supabase.from('usuario').update({
        'nome': usuario.nome,
        'apelido': usuario.apelido,
        'email': usuario.email,
        'senha_hash': usuario.senhaHash,
        'telefone': usuario.telefone,
        'idperfil': usuario.idPerfil,
        'primeira_senha': usuario.primeiraSenha,
        'ativo': usuario.ativo,
      }).eq('id_usuario', usuario.id!);
      
      print('✅ Usuário ${usuario.id} atualizado no Supabase');
      
    } catch (e) {
      print('⚠️ Erro ao sincronizar atualização: $e');
      _addToOfflineQueue(OfflineOperation(
        type: 'update_usuario',
        data: {'usuario': usuario.toMap()},
        timestamp: DateTime.now(),
      ));
    }
  } else if (!_isOnline) {
    _addToOfflineQueue(OfflineOperation(
      type: 'update_usuario',
      data: {'usuario': usuario.toMap()},
      timestamp: DateTime.now(),
    ));
  }
  
  return result;
}

Future<int> deleteUsuario(int id) async {
  // 1. Deletar localmente PRIMEIRO
  final result = await _localDb.deleteUsuario(id);
  
  // 2. Sincronizar com Supabase
  if (_isOnline) {
    try {
      await _supabase
          .from('usuario')
          .delete()
          .eq('id_usuario', id);
      
      print('✅ Usuário $id deletado do Supabase');
      
    } catch (e) {
      print('⚠️ Erro ao sincronizar exclusão: $e');
      
      // 🔥 ADICIONAR À FILA OFFLINE
      _addToOfflineQueue(OfflineOperation(
        type: 'delete_usuario',
        data: {'id_usuario': id},
        timestamp: DateTime.now(),
      ));
    }
  } else {
    // 3. Se OFFLINE, adicionar à fila
    _addToOfflineQueue(OfflineOperation(
      type: 'delete_usuario',
      data: {'id_usuario': id},
      timestamp: DateTime.now(),
    ));
  }
  
  return result;
}

Future<int> toggleAtivoUsuario(int id, bool isActive) async {
  // 1. Atualizar localmente PRIMEIRO
  final result = await _localDb.toggleAtivoUsuario(id, isActive);
  
  // 2. Sincronizar com Supabase
  if (_isOnline) {
    try {
      await _supabase.from('usuario').update({
        'ativo': isActive ? 1 : 0,
      }).eq('id_usuario', id);
      
      print('✅ Status do usuário $id atualizado no Supabase');
      
    } catch (e) {
      print('⚠️ Erro ao sincronizar status: $e');
      _addToOfflineQueue(OfflineOperation(
        type: 'toggle_ativo_usuario',
        data: {
          'id_usuario': id,
          'ativo': isActive ? 1 : 0,
        },
        timestamp: DateTime.now(),
      ));
    }
  } else {
    _addToOfflineQueue(OfflineOperation(
      type: 'toggle_ativo_usuario',
      data: {
        'id_usuario': id,
        'ativo': isActive ? 1 : 0,
      },
      timestamp: DateTime.now(),
    ));
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
// SINCRONIZAÇÃO SELETIVA (NOVA FUNCIONALIDADE)
// ==========================================


Future<void> sincronizarSeletivo({
  List<int>? produtosIds,
  List<int>? categoriasIds,
  List<int>? pedidosIds,
  List<int>? usuariosIds,
  bool sincronizarMovimentos = false,
}) async {
  if (!_isOnline) {
    print('⚠️ Dispositivo offline - sincronização seletiva adiada');
    return;
  }

  try {
    print('🔄 Iniciando sincronização seletiva...');
    int totalSincronizado = 0;

    // Sincronizar categorias específicas
    if (categoriasIds != null && categoriasIds.isNotEmpty) {
      await _syncCategoriasEspecificas(categoriasIds);
      totalSincronizado += categoriasIds.length;
    }

    // Sincronizar produtos específicos
    if (produtosIds != null && produtosIds.isNotEmpty) {
      await _syncProdutosEspecificos(produtosIds);
      totalSincronizado += produtosIds.length;
    }

    // Sincronizar pedidos específicos
    if (pedidosIds != null && pedidosIds.isNotEmpty) {
      await _syncPedidosEspecificos(pedidosIds);
      totalSincronizado += pedidosIds.length;
    }

    // Sincronizar usuários específicos
    if (usuariosIds != null && usuariosIds.isNotEmpty) {
      await _syncUsuariosEspecificos(usuariosIds);
      totalSincronizado += usuariosIds.length;
    }

    // Sincronizar movimentos de estoque se solicitado
    if (sincronizarMovimentos) {
      await _syncMovimentosEstoque();
      print('✅ Movimentos de estoque sincronizados');
    }

    print('✅ Sincronização seletiva concluída ($totalSincronizado registros)');
  } catch (e) {
    print('❌ Erro na sincronização seletiva: $e');
  }
}

// ==========================================
// MÉTODOS AUXILIARES DE SYNC SELETIVO
// ==========================================

/// Sincroniza apenas categorias com IDs específicos
Future<void> _syncCategoriasEspecificas(List<int> ids) async {
  try {
    print('🔄 Sincronizando ${ids.length} categorias...');
    
    final response = await _supabase
        .from('categorias')
        .select('*')
        .inFilter('id_categoria', ids);

    final db = await _localDb.database;
    
    for (final catMap in response) {
      final idCategoria = catMap['id_categoria'] as int?;
      if (idCategoria == null) continue;
      
      final categoria = Categoria(
        id: idCategoria,
        nome: catMap['nome_categoria'] as String? ?? 'Sem nome',
        descricao: catMap['descricao'] as String?,
      );

      final existente = await db.query(
        'categoria',
        where: 'id_categoria = ?',
        whereArgs: [idCategoria],
        limit: 1,
      );

      if (existente.isEmpty) {
        await _localDb.createCategoriaComIdEspecifico(categoria, []);
        print('  ✅ Categoria $idCategoria criada localmente');
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
        print('  ✅ Categoria $idCategoria atualizada localmente');
      }
    }

    print('✅ ${response.length} categorias sincronizadas seletivamente');
  } catch (e) {
    print('❌ Erro ao sincronizar categorias específicas: $e');
    rethrow;
  }
}

/// Sincroniza apenas produtos com IDs específicos
Future<void> _syncProdutosEspecificos(List<int> ids) async {
  try {
    print('🔄 Sincronizando ${ids.length} produtos...');
    
    final response = await _supabase
        .from('produtos')
        .select('*')
        .inFilter('id_produto', ids);

    for (final produtoMap in response) {
      await _syncProdutoFromSupabase(produtoMap);
    }

    print('✅ ${response.length} produtos sincronizados seletivamente');
  } catch (e) {
    print('❌ Erro ao sincronizar produtos específicos: $e');
    rethrow;
  }
}

/// Sincroniza apenas pedidos com IDs específicos
Future<void> _syncPedidosEspecificos(List<int> ids) async {
  try {
    print('🔄 Sincronizando ${ids.length} pedidos...');
    
    final response = await _supabase
        .from('pedidos')
        .select('*')
        .inFilter('id_pedido', ids);

    final db = await _localDb.database;

    for (final pedidoMap in response) {
      final idPedido = pedidoMap['id_pedido'] as int?;
      if (idPedido == null) continue;

      final idTipoPagamento = pedidoMap['idtipo_pagamento'] as int?;
      if (idTipoPagamento == null) {
        print('⚠️ Pedido $idPedido sem tipo_pagamento - pulando');
        continue;
      }

      final pedidoData = {
        'id_pedido': idPedido,
        'reference': pedidoMap['reference'],
         'nome_pedido': pedidoMap['nome_pedido'],
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

      final existente = await db.query(
        'pedido',
        where: 'id_pedido = ?',
        whereArgs: [idPedido],
        limit: 1,
      );

      if (existente.isEmpty) {
        await db.insert('pedido', pedidoData);
        print('  ✅ Pedido $idPedido inserido localmente');
      } else {
        await db.update(
          'pedido',
          pedidoData,
          where: 'id_pedido = ?',
          whereArgs: [idPedido],
        );
        print('  ✅ Pedido $idPedido atualizado localmente');
      }

      // Sincronizar itens do pedido
      try {
        final itensResponse = await _supabase
            .from('itens_pedido')
            .select('*')
            .eq('id_pedido', idPedido);

        await db.delete(
          'item_pedido',
          where: 'id_pedido = ?',
          whereArgs: [idPedido],
        );

        for (final itemMap in itensResponse) {
          final idProduto = itemMap['id_produto'] as int?;
          if (idProduto == null) continue;

          // Validar se produto existe localmente
          final produtoExiste = await db.query(
            'produto',
            columns: ['id_produto'],
            where: 'id_produto = ?',
            whereArgs: [idProduto],
            limit: 1,
          );

          if (produtoExiste.isEmpty) {
            print('  ⚠️ Produto $idProduto não existe - sincronizando...');
            await _syncProdutosEspecificos([idProduto]);
          }

          await db.insert('item_pedido', {
            'id_item_pedido': itemMap['id_item_pedido'],
            'id_pedido': idPedido,
            'id_produto': idProduto,
            'quantidade': itemMap['quantidade'],
            'preco_unitario': itemMap['preco_unitario'],
            'subtotal': itemMap['subtotal'],
          });
        }

        print('  ✅ ${itensResponse.length} itens sincronizados para pedido $idPedido');
      } catch (e) {
        print('  ⚠️ Erro ao sincronizar itens: $e');
      }
    }

    print('✅ ${response.length} pedidos sincronizados seletivamente');
  } catch (e) {
    print('❌ Erro ao sincronizar pedidos específicos: $e');
    rethrow;
  }
}

/// Sincroniza apenas usuários com IDs específicos
Future<void> _syncUsuariosEspecificos(List<int> ids) async {
  try {
    print('🔄 Sincronizando ${ids.length} usuários...');
    
    final response = await _supabase
        .from('usuario')
        .select('*')
        .inFilter('id_usuario', ids);

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

      final existente = await db.query(
        'usuario',
        where: 'id_usuario = ?',
        whereArgs: [idUsuario],
        limit: 1,
      );

      if (existente.isEmpty) {
        await db.insert('usuario', usuario.toMap());
        print('  ✅ Usuário $idUsuario inserido localmente');
      } else {
        await db.update(
          'usuario',
          usuario.toMap(),
          where: 'id_usuario = ?',
          whereArgs: [idUsuario],
        );
        print('  ✅ Usuário $idUsuario atualizado localmente');
      }
    }

    print('✅ ${response.length} usuários sincronizados seletivamente');
  } catch (e) {
    print('❌ Erro ao sincronizar usuários específicos: $e');
    rethrow;
  }
}

/// Sincroniza apenas movimentos de estoque com IDs específicos
Future<void> _syncMovimentosEspecificos(List<int> ids) async {
  try {
    print('🔄 Sincronizando ${ids.length} movimentos de estoque...');
    
    final response = await _supabase
        .from('movimento_estoque')
        .select('*')
        .inFilter('id_movimento', ids);

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
        print('  ✅ Movimento $idMovimento inserido localmente');
      } else {
        await db.update(
          'movimento_estoque',
          movimentoData,
          where: 'id_movimento = ?',
          whereArgs: [idMovimento],
        );
        print('  ✅ Movimento $idMovimento atualizado localmente');
      }
    }

    print('✅ ${response.length} movimentos sincronizados seletivamente');
  } catch (e) {
    print('❌ Erro ao sincronizar movimentos específicos: $e');
    rethrow;
  }
}

void _setupRealtimeListeners() {
  print('🔧 Configurando listeners Realtime com broadcast de eventos...');

  // ==========================================
  // LISTENER PARA CATEGORIAS
  // ==========================================
  _categoriasChannel = _supabase
      .channel('categorias_changes')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'categorias',
        callback: (payload) async {
          print('🔔 Mudança detectada em categorias: ${payload.eventType}');
          
          // ✅ CORRETO: Verificação de device_id
          if (payload.newRecord?['device_id'] == _deviceId) {
            print('⏭️  Ignorando mudança criada por este dispositivo');
            return;
          }
          
          // ✅ CORRETO: Tratamento de DELETE
          if (payload.eventType == PostgresChangeEvent.delete) {
            final idCategoria = payload.oldRecord?['id_categoria'] as int?;
            if (idCategoria != null) {
              print('🗑️  Categoria $idCategoria deletada - removendo localmente...');
              
              final db = await _localDb.database;
              await db.delete(
                'categoria',
                where: 'id_categoria = ?',
                whereArgs: [idCategoria],
              );
              
              // ✅ CORRETO: Emitir evento após delete
              SyncEventsService.instance.emitir(
                SyncEventType.categoriaAlterada,
                idEntidade: idCategoria,
              );
              
              print('✅ Categoria $idCategoria deletada + evento emitido');
            }
            return;
          }
          
          // ✅ CORRETO: Tratamento de INSERT/UPDATE
          final idCategoria = payload.newRecord?['id_categoria'] as int?;
          if (idCategoria != null) {
            print('🔄 Sincronizando apenas categoria $idCategoria...');
            
            try {
              await _syncCategoriasEspecificas([idCategoria]);
              
              // ✅ CORRETO: Emitir evento APÓS sincronização
              SyncEventsService.instance.emitir(
                SyncEventType.categoriaAlterada,
                idEntidade: idCategoria,
              );
              
              print('✅ Categoria $idCategoria sincronizada + evento emitido');
            } catch (e) {
              print('❌ Erro ao sincronizar categoria $idCategoria: $e');
            }
          }
        },
      )
      .subscribe();

  // ==========================================
  // LISTENER PARA PRODUTOS
  // ==========================================
  _produtosChannel = _supabase
      .channel('produtos_changes')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'produtos',
        callback: (payload) async {
          print('🔔 Mudança detectada em produtos: ${payload.eventType}');
          
          // ✅ CORRETO: Verificação de device_id
          if (payload.newRecord?['device_id'] == _deviceId) {
            print('⏭️  Ignorando mudança criada por este dispositivo');
            return;
          }
          
          // ✅ CORRETO: Tratamento de DELETE
          if (payload.eventType == PostgresChangeEvent.delete) {
            final idProduto = payload.oldRecord?['id_produto'] as int?;
            if (idProduto != null) {
              print('🗑️  Produto $idProduto deletado - removendo localmente...');
              
              final db = await _localDb.database;
              await db.delete('produto', where: 'id_produto = ?', whereArgs: [idProduto]);
              await db.delete('produto_categoria', where: 'id_produto = ?', whereArgs: [idProduto]);
              await db.delete('produto_imagem', where: 'id_produto = ?', whereArgs: [idProduto]);
              
              // ✅ CORRETO: Emitir eventos
              SyncEventsService.instance.emitir(
                SyncEventType.produtoAlterado,
                idEntidade: idProduto,
              );
              SyncEventsService.instance.emitir(SyncEventType.estoqueAlterado);
              notificarMudancaEstoque(); // Manter para compatibilidade
              
              print('✅ Produto $idProduto deletado + eventos emitidos');
            }
            return;
          }
          
          // ✅ CORRETO: Tratamento de INSERT/UPDATE
          final idProduto = payload.newRecord?['id_produto'] as int?;
          if (idProduto != null) {
            print('🔄 Sincronizando apenas produto $idProduto...');
            
            try {
              await _syncProdutosEspecificos([idProduto]);
              
              // ✅ CORRETO: Emitir eventos APÓS sincronização
              SyncEventsService.instance.emitir(
                SyncEventType.produtoAlterado,
                idEntidade: idProduto,
              );
              SyncEventsService.instance.emitir(SyncEventType.estoqueAlterado);
              notificarMudancaEstoque(); // Manter para compatibilidade
              
              print('✅ Produto $idProduto sincronizado + eventos emitidos');
            } catch (e) {
              print('❌ Erro ao sincronizar produto $idProduto: $e');
            }
          }
        },
      )
      .subscribe();

  // ==========================================
  // LISTENER PARA PEDIDOS
  // ==========================================
  _pedidosChannel = _supabase
      .channel('pedidos_changes')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'pedidos',
        callback: (payload) async {
          print('🔔 Mudança detectada em pedidos: ${payload.eventType}');
          
          // ✅ CORRETO: Verificação de device_id
          if (payload.newRecord?['device_id'] == _deviceId) {
            print('⏭️  Ignorando mudança criada por este dispositivo');
            return;
          }
          
          // ✅ CORRETO: Tratamento de DELETE
          if (payload.eventType == PostgresChangeEvent.delete) {
            final idPedido = payload.oldRecord?['id_pedido'] as int?;
            if (idPedido != null) {
              print('🗑️  Pedido $idPedido deletado - removendo localmente...');
              
              final db = await _localDb.database;
              await db.delete('item_pedido', where: 'id_pedido = ?', whereArgs: [idPedido]);
              await db.delete('pedido', where: 'id_pedido = ?', whereArgs: [idPedido]);
              
              // ✅ CORRETO: Emitir evento
              SyncEventsService.instance.emitir(
                SyncEventType.pedidoAlterado,
                idEntidade: idPedido,
              );
              
              print('✅ Pedido $idPedido deletado + evento emitido');
            }
            return;
          }
          
          // ✅ CORRETO: Tratamento de INSERT/UPDATE
          final idPedido = payload.newRecord?['id_pedido'] as int?;
          if (idPedido != null) {
            print('🔄 Sincronizando apenas pedido $idPedido...');
            
            try {
              await _syncPedidosEspecificos([idPedido]);
              
              // ✅ CORRETO: Emitir evento APÓS sincronização
              SyncEventsService.instance.emitir(
                SyncEventType.pedidoAlterado,
                idEntidade: idPedido,
              );
              
              print('✅ Pedido $idPedido sincronizado + evento emitido');
            } catch (e) {
              print('❌ Erro ao sincronizar pedido $idPedido: $e');
            }
          }
        },
      )
      .subscribe();

  // ==========================================
  // 🔥 LISTENER PARA MOVIMENTOS DE ESTOQUE (CORRIGIDO)
  // ==========================================
  _movimentosChannel = _supabase  // 🔥 CRIAR VARIÁVEL _movimentosChannel
      .channel('movimentos_estoque_changes')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'movimento_estoque',
        callback: (payload) async {
          print('🔔 Mudança detectada em movimentos: ${payload.eventType}');
          
          // ✅ CORRETO: Verificação de device_id
          if (payload.newRecord?['device_id'] == _deviceId) {
            print('⏭️  Ignorando mudança criada por este dispositivo');
            return;
          }
          
          // 🔥 CORREÇÃO: Adicionar tratamento de DELETE
          if (payload.eventType == PostgresChangeEvent.delete) {
            final idMovimento = payload.oldRecord?['id_movimento'] as int?;
            final idProduto = payload.oldRecord?['id_produto'] as int?;
            
            if (idMovimento != null) {
              print('🗑️  Movimento $idMovimento deletado');
              
              final db = await _localDb.database;
              await db.delete(
                'movimento_estoque',
                where: 'id_movimento = ?',
                whereArgs: [idMovimento],
              );
              
              // Atualizar estoque do produto se soubermos qual é
              if (idProduto != null) {
                await _syncProdutosEspecificos([idProduto]);
                SyncEventsService.instance.emitir(
                  SyncEventType.estoqueAlterado,
                  idEntidade: idProduto,
                );
              } else {
                SyncEventsService.instance.emitir(SyncEventType.estoqueAlterado);
              }
              
              notificarMudancaEstoque();
              print('✅ Movimento deletado + estoque atualizado');
            }
            return;
          }
          
          // ✅ CORRETO: Tratamento de INSERT/UPDATE
          final idMovimento = payload.newRecord?['id_movimento'] as int?;
          final idProduto = payload.newRecord?['id_produto'] as int?;

          if (idMovimento != null && idProduto != null) {
            print('🔄 Sincronizando movimento $idMovimento (produto $idProduto)...');
            
            try {
              await _syncMovimentosEspecificos([idMovimento]);
              await _syncProdutosEspecificos([idProduto]);
              
              // ✅ CORRETO: Emitir eventos
              SyncEventsService.instance.emitir(
                SyncEventType.movimentoAlterado,  // 🔥 ADICIONAR este tipo
                idEntidade: idMovimento,
              );
              SyncEventsService.instance.emitir(
                SyncEventType.estoqueAlterado,
                idEntidade: idProduto,
              );
              notificarMudancaEstoque();
              
              print('✅ Movimento $idMovimento sincronizado + eventos emitidos');
            } catch (e) {
              print('❌ Erro ao sincronizar movimento $idMovimento: $e');
            }
          }
        },
      )
      .subscribe();

  print('✅ Todos os listeners Realtime configurados com sistema de eventos!');
}

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

// 🔥 ADICIONAR este método na classe SupabaseSyncService

/// Sincroniza imagens locais com Supabase Storage
Future<void> sincronizarImagensProdutos() async {
  try {
    // Buscar produtos com imagens não sincronizadas (caminhos locais)
   final db = await _localDb.database;
    
    final List<Map<String, dynamic>> imagensLocais = await db.rawQuery('''
      SELECT pi.id, pi.caminho, pi.id_produto
      FROM produto_imagem pi
      WHERE pi.caminho NOT LIKE 'http%'
    ''');
    
    for (final row in imagensLocais) {
      final id = row['id'] as int;
      final caminhoLocal = row['caminho'] as String;
      
      // Fazer upload para Supabase
      final publicUrl = await SupabaseStorageService.instance.uploadImagem(caminhoLocal);
      
      if (publicUrl != null) {
        // Atualizar caminho no banco
        await db.update(
          'produto_imagem',
          {'caminho': publicUrl},
          where: 'id = ?',
          whereArgs: [id],
        );
        
        print('✅ Imagem sincronizada: $id -> $publicUrl');
      }
    }
    
  } catch (e) {
    print('❌ Erro ao sincronizar imagens: $e');
  }
}


  // ==========================================
  // MÉTODO PARA FECHAR O BANCO
  // ==========================================

  Future<void> close() async {
    await _localDb.close();
  }
}

