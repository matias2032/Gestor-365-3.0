import 'dart:async';
import 'base_de_dados.dart';
import 'supabase_sync_service.dart'; 

/// Service global para gerenciar o contador de pedidos por finalizar
/// Mantém todos os widgets sincronizados automaticamente
class PedidoContadorService {
  // Singleton
  static final PedidoContadorService instance = PedidoContadorService._internal();
  factory PedidoContadorService() => instance;
  PedidoContadorService._internal();

  final DatabaseService _dbService = DatabaseService.instance;
   final SupabaseSyncService _syncService = SupabaseSyncService.instance; 

  // Stream para notificar mudanças no contador
  final _contadorStreamController = StreamController<int>.broadcast();
  Stream<int> get contadorStream => _contadorStreamController.stream;

  // Valor atual do contador
  int _contadorAtual = 0;
  int get contadorAtual => _contadorAtual;

  // Flag para evitar múltiplas cargas simultâneas
  bool _isLoading = false;

  /// 🔥 NOVO: Carrega o contador do banco de dados
  /// Deve ser chamado após o login
  /// Carrega o contador do banco de dados
  Future<void> carregarContador(int idUsuario) async {
    if (_isLoading) return;
    
    _isLoading = true;
    try {
      // 🔥 USAR SYNC SERVICE para garantir dados atualizados
      final pedidos = await _syncService.readPedidosPorFinalizar(idUsuario);
      atualizarContador(pedidos.length);
    } catch (e) {
      print('Erro ao carregar contador de pedidos: $e');
      atualizarContador(0);
    } finally {
      _isLoading = false;
    }
  }

  /// Atualiza o contador e notifica todos os listeners
  void atualizarContador(int novoValor) {
    if (_contadorAtual != novoValor) {
      _contadorAtual = novoValor;
      _contadorStreamController.add(_contadorAtual);
    }
  }

  /// Incrementa o contador em 1
  void incrementar() {
    atualizarContador(_contadorAtual + 1);
  }

  /// Decrementa o contador em 1
  void decrementar() {
    if (_contadorAtual > 0) {
      atualizarContador(_contadorAtual - 1);
    }
  }

  /// Reseta o contador para 0
  void resetar() {
    atualizarContador(0);
  }

  /// Libera recursos
  void dispose() {
    _contadorStreamController.close();
  }
}