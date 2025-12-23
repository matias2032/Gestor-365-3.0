// lib/services/servico_logs.dart

import 'base_de_dados.dart';
import 'sessao_service.dart';

class ServicoLogs {
  static final ServicoLogs instance = ServicoLogs._internal();
  ServicoLogs._internal();

  final DatabaseService _db = DatabaseService.instance;

  /// Registra um log no sistema
  Future<void> registrarLog(String acao, {int? idUsuario}) async {
    try {
      // Se não forneceu ID, tenta pegar da sessão
      final userId = idUsuario ?? SessaoService.instance.usuarioAtual?.id;

      final db = await _db.database;
      await db.insert('logs', {
        'id_usuario': userId,
        'acao': acao,
        'data_hora': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Erro ao registrar log: $e');
      // Não lança exceção para não quebrar o fluxo da aplicação
    }
  }

  // ============================================
  // MÉTODOS DE CONVENIÊNCIA PARA LOGS COMUNS
  // ============================================

  Future<void> registrarLogin(int idUsuario, String nomeUsuario) async {
    await registrarLog('Login realizado por $nomeUsuario', idUsuario: idUsuario);
  }

  Future<void> registrarLogout(int idUsuario, String nomeUsuario) async {
    await registrarLog('Logout realizado por $nomeUsuario', idUsuario: idUsuario);
  }

  // --- USUÁRIOS ---
  Future<void> registrarCadastroUsuario(String nomeUsuario) async {
    await registrarLog('Cadastro de usuário: $nomeUsuario');
  }

  Future<void> registrarEdicaoUsuario(String nomeUsuario) async {
    await registrarLog('Edição de usuário: $nomeUsuario');
  }

  Future<void> registrarExclusaoUsuario(String nomeUsuario) async {
    await registrarLog('Exclusão de usuário: $nomeUsuario');
  }

  Future<void> registrarAlteracaoSenha(String nomeUsuario) async {
    await registrarLog('Alteração de senha do usuário: $nomeUsuario');
  }

  Future<void> registrarToggleUsuario(String nomeUsuario, bool ativo) async {
    final status = ativo ? 'ativado' : 'desativado';
    await registrarLog('Usuário $nomeUsuario foi $status');
  }

  // --- CATEGORIAS ---
  Future<void> registrarCadastroCategoria(String nomeCategoria) async {
    await registrarLog('Cadastro de categoria: $nomeCategoria');
  }

  Future<void> registrarEdicaoCategoria(String nomeCategoria) async {
    await registrarLog('Edição de categoria: $nomeCategoria');
  }

  Future<void> registrarExclusaoCategoria(String nomeCategoria) async {
    await registrarLog('Exclusão de categoria: $nomeCategoria');
  }

  // --- PRODUTOS ---
  Future<void> registrarCadastroProduto(String nomeProduto) async {
    await registrarLog('Cadastro de produto: $nomeProduto');
  }

  Future<void> registrarEdicaoProduto(String nomeProduto) async {
    await registrarLog('Edição de produto: $nomeProduto');
  }

  Future<void> registrarExclusaoProduto(String nomeProduto) async {
    await registrarLog('Exclusão de produto: $nomeProduto');
  }

  // --- PEDIDOS ---
  Future<void> registrarCriacaoPedido(int idPedido, double total) async {
    await registrarLog('Criação de pedido #$idPedido - Total: MZN ${total.toStringAsFixed(2)}');
  }

  Future<void> registrarFinalizacaoPedido(int idPedido, String tipoPagamento) async {
    await registrarLog('Finalização de pedido #$idPedido - Pagamento: $tipoPagamento');
  }

  Future<void> registrarCancelamentoPedido(int idPedido, String motivo) async {
    await registrarLog('Cancelamento de pedido #$idPedido - Motivo: $motivo');
  }

  Future<void> registrarAdicaoItemPedido(int idPedido, String nomeProduto, int quantidade) async {
    await registrarLog('Adicionado $quantidade x $nomeProduto ao pedido #$idPedido');
  }

  Future<void> registrarRemocaoItemPedido(int idPedido, String nomeProduto) async {
    await registrarLog('Removido $nomeProduto do pedido #$idPedido');
  }

  Future<void> registrarAtualizacaoItemPedido(int idPedido, String nomeProduto, int novaQtd) async {
    await registrarLog('Atualizada quantidade de $nomeProduto para $novaQtd no pedido #$idPedido');
  }

  // --- OUTROS ---
  Future<void> registrarGeracaoFatura(int idPedido) async {
    await registrarLog('Geração de fatura do pedido #$idPedido');
  }

  Future<void> registrarAcaoPersonalizada(String descricao) async {
    await registrarLog(descricao);
  }
}