// lib/services/pedido_ativo_service.dart

/// Serviço Singleton para gerenciar o pedido ativo/selecionado
/// Permite que diferentes telas saibam qual pedido está sendo editado
class PedidoAtivoService {
  static final PedidoAtivoService instance = PedidoAtivoService._init();
  
  PedidoAtivoService._init();
  
  int? _pedidoAtivoId;
  
  /// Obtém o ID do pedido atualmente ativo
  int? get pedidoAtivoId => _pedidoAtivoId;
  
  /// Define um pedido como ativo
  void setPedidoAtivo(int idPedido) {
    _pedidoAtivoId = idPedido;
  }
  
  /// Limpa a seleção de pedido ativo
  void limparPedidoAtivo() {
    _pedidoAtivoId = null;
  }
  
  /// Verifica se há um pedido ativo
  bool get temPedidoAtivo => _pedidoAtivoId != null;
}