// lib/services/pedido_contador_service.dart

import 'dart:async';
import 'base_de_dados.dart';
import 'sessao_service.dart'; // 🔥 NOVO IMPORT

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

  // 🔥 NOVO: Timestamp da última atualização
  DateTime? _ultimaAtualizacao;

  /// 🔥 MÉTODO CORRIGIDO: Carrega o contador do banco LOCAL
  /// Não dispara sincronização - apenas leitura pura
  Future<void> carregarContador(int idUsuario) async {
    // Evitar cargas simultâneas
    if (_isLoading) {
      print('⏳ Já existe um carregamento em andamento');
      return;
    }

    _isLoading = true;

    try {
      print('📊 Carregando contador de pedidos (usuário $idUsuario)...');
      
      // 🔥 LEITURA PURA DO BANCO LOCAL (SEM SINCRONIZAÇÃO)
      final pedidos = await _dbService.readPedidosPorFinalizar(idUsuario);
      final novoContador = pedidos.length;
      
      atualizarContador(novoContador);
      _ultimaAtualizacao = DateTime.now();
      
      print('✅ Contador carregado: $novoContador pedidos');
      
    } catch (e) {
      print('❌ Erro ao carregar contador: $e');
      // Não altera o contador em caso de erro
    } finally {
      _isLoading = false;
    }
  }

  /// 🔥 NOVO: Recarrega o contador se necessário (cache inteligente)
  /// Usa cache se a última atualização foi recente (< 30 segundos)
  Future<void> recarregarSeNecessario() async {
    final usuario = SessaoService.instance.usuarioAtual;
    if (usuario == null) {
      print('⚠️ Nenhum usuário logado - não é possível recarregar contador');
      return;
    }

    final agora = DateTime.now();
    
    // 🔥 CACHE: Só recarrega se passou mais de 30 segundos
    if (_ultimaAtualizacao != null &&
        agora.difference(_ultimaAtualizacao!).inSeconds < 30) {
      print('✅ Usando contador em cache ($_contadorAtual)');
      return;
    }

    print('🔄 Cache expirado - recarregando contador...');
    await carregarContador(usuario.id!);
  }

  /// Atualiza o contador e notifica todos os listeners
  void atualizarContador(int novoValor) {
    if (_contadorAtual != novoValor) {
      print('📊 Contador atualizado: $_contadorAtual → $novoValor');
      _contadorAtual = novoValor;
      _contadorStreamController.add(_contadorAtual);
      _ultimaAtualizacao = DateTime.now(); // 🔥 Atualiza timestamp
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

  /// Reseta o contador para 0 (usado no logout)
  void resetar() {
    print('🔄 Resetando contador de pedidos');
    _contadorAtual = 0;
    _ultimaAtualizacao = null;
    _contadorStreamController.add(0);
  }

  /// 🔥 NOVO: Invalida o cache forçando próxima leitura do banco
  void invalidarCache() {
    print('⚠️ Cache do contador invalidado');
    _ultimaAtualizacao = null;
  }

  /// Libera recursos
  void dispose() {
    _contadorStreamController.close();
  }
}