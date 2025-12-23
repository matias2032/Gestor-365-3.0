import 'dart:async';
import 'base_de_dados.dart';

/// Service global para gerenciar o contador de pedidos por finalizar
/// Mantém todos os widgets sincronizados automaticamente
class PedidoContadorService {
  // Singleton
  static final PedidoContadorService instance = PedidoContadorService._internal();
  factory PedidoContadorService() => instance;
  PedidoContadorService._internal();

  final DatabaseService _dbService = DatabaseService.instance;

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
  Future<void> carregarContador(int idUsuario) async {
    if (_isLoading) return; // Evita múltiplas cargas simultâneas
    
    _isLoading = true;
    try {
      final pedidos = await _dbService.readPedidosPorFinalizar(idUsuario);
      atualizarContador(pedidos.length);
    } catch (e) {
      print('Erro ao carregar contador de pedidos: $e');
      atualizarContador(0); // Define como 0 em caso de erro
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