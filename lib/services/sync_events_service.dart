// lib/services/sync_events_service.dart

import 'dart:async';

/// Tipos de eventos de sincronização que podem ocorrer
enum SyncEventType {
  produtoAlterado,
  categoriaAlterada,
  pedidoAlterado,
  estoqueAlterado,
  movimentoAlterado,
  syncCompleta,
}

/// Representa um evento de sincronização
class SyncEvent {
  final SyncEventType tipo;
  final int? idEntidade;
  final DateTime timestamp;
  final Map<String, dynamic>? dadosAdicionais;
  
  SyncEvent({
    required this.tipo,
    this.idEntidade,
    this.dadosAdicionais,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'SyncEvent(tipo: $tipo, id: $idEntidade, timestamp: $timestamp)';
  }
}

/// Serviço singleton para gerenciar eventos de sincronização
/// 
/// Este serviço permite que diferentes partes do app sejam notificadas
/// quando dados são sincronizados via Realtime do Supabase.
/// 
/// Uso:
/// ```dart
/// // Emitir evento (no sync_service.dart):
/// SyncEventsService.instance.emitir(SyncEventType.produtoAlterado, idEntidade: 123);
/// 
/// // Escutar eventos (nas telas):
/// _subscription = SyncEventsService.instance.eventStream.listen((event) {
///   if (event.tipo == SyncEventType.produtoAlterado) {
///     setState(() { /* atualizar UI */ });
///   }
/// });
/// ```
class SyncEventsService {
  // Singleton
  static final SyncEventsService instance = SyncEventsService._internal();
  
  SyncEventsService._internal() {
    print('🔥 SyncEventsService inicializado');
  }

  // Stream controller broadcast (permite múltiplos listeners)
  final _eventController = StreamController<SyncEvent>.broadcast();
  
  /// Stream de eventos que pode ser escutado por qualquer widget
  Stream<SyncEvent> get eventStream => _eventController.stream;
  
  /// Emite um evento de sincronização
  /// 
  /// [tipo] - Tipo do evento (produto, categoria, pedido, etc)
  /// [idEntidade] - ID opcional da entidade alterada
  /// [dadosAdicionais] - Dados extras opcionais
  void emitir(
    SyncEventType tipo, {
    int? idEntidade,
    Map<String, dynamic>? dadosAdicionais,
  }) {
    final event = SyncEvent(
      tipo: tipo,
      idEntidade: idEntidade,
      dadosAdicionais: dadosAdicionais,
    );
    
    _eventController.add(event);
    
    // Log para debug
    print('📡 Evento emitido: ${event.tipo}${idEntidade != null ? " (ID: $idEntidade)" : ""}');
  }
  
  /// Emite evento de produto alterado
  void emitirProdutoAlterado(int idProduto) {
    emitir(SyncEventType.produtoAlterado, idEntidade: idProduto);
  }
  
  /// Emite evento de categoria alterada
  void emitirCategoriaAlterada(int idCategoria) {
    emitir(SyncEventType.categoriaAlterada, idEntidade: idCategoria);
  }
  
  /// Emite evento de pedido alterado
  void emitirPedidoAlterado(int idPedido) {
    emitir(SyncEventType.pedidoAlterado, idEntidade: idPedido);
  }
  
  /// Emite evento de estoque alterado
  void emitirEstoqueAlterado({int? idProduto}) {
    emitir(SyncEventType.estoqueAlterado, idEntidade: idProduto);
  }
  
  /// Emite evento de movimento alterado
  void emitirMovimentoAlterado(int idMovimento) {
    emitir(SyncEventType.movimentoAlterado, idEntidade: idMovimento);
  }
  
  /// Emite evento de sincronização completa
  void emitirSyncCompleta({Map<String, dynamic>? estatisticas}) {
    emitir(
      SyncEventType.syncCompleta,
      dadosAdicionais: estatisticas,
    );
  }
  
  /// Dispose do controller (chamar apenas ao encerrar o app)
  void dispose() {
    print('🔥 SyncEventsService disposing...');
    _eventController.close();
  }
  
  /// Verifica se há listeners ativos
  bool get hasListeners => _eventController.hasListener;
  
  /// Número de listeners ativos
  int get listenerCount => _eventController.hasListener ? 1 : 0;
}