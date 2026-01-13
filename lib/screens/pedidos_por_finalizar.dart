// lib/screens/pedidos_por_finalizar.dart - VERSÃO UNIFICADA

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../models/pedido.dart';
import '../models/produto_imagem.dart';
import '../services/base_de_dados.dart';
import '../services/pedido_ativo_service.dart';
import '../services/pedido_contador_service.dart';
import '../services/supabase_sync_service.dart';
import '../services/sessao_service.dart';

class PedidosPorFinalizarScreen extends StatefulWidget {
  const PedidosPorFinalizarScreen({super.key});

  @override
  State<PedidosPorFinalizarScreen> createState() => _PedidosPorFinalizarScreenState();
}

class _PedidosPorFinalizarScreenState extends State<PedidosPorFinalizarScreen> {
  final DatabaseService _dbService = DatabaseService.instance;
  final PedidoAtivoService _pedidoAtivoService = PedidoAtivoService.instance;
  final PedidoContadorService _contadorService = PedidoContadorService.instance;
  final SupabaseSyncService _syncService = SupabaseSyncService.instance;
  
  late Future<List<Pedido>> _pedidosFuture;
  int? _pedidoAtivoId;
  int? _pedidoExpandidoId; // Controla qual pedido está expandido
    bool _cancelando = false; // 

  @override
  void initState() {
    super.initState();
    _pedidoAtivoId = _pedidoAtivoService.pedidoAtivoId;
    _pedidosFuture = _carregarPedidos();
  }

  Future<List<Pedido>> _carregarPedidos() async {
    final usuario = SessaoService.instance.usuarioAtual;
    if (usuario == null) return [];
    
    final pedidos = await _syncService.readPedidosPorFinalizar(usuario.id!);
    _contadorService.atualizarContador(pedidos.length);
    
    return pedidos;
  }

  void _refreshPedidos() {
    setState(() {
      _pedidosFuture = _carregarPedidos();
    });
  }

  Future<void> _confirmarCancelamento(Pedido pedido) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Pedido'),
        content: Text(
          'Tem certeza que deseja cancelar o Pedido #${pedido.id}? '
          'O estoque será restaurado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sim, Cancelar'),
          ),
        ],
      ),
    );

    if (confirmado == true) {
      await _cancelarPedido(pedido);
    }
  }

  Future<void> _cancelarPedido(Pedido pedido) async {
    // 🔥 NOVO: Bloquear TODOS os botões imediatamente
    setState(() => _cancelando = true);
    
    try {
      await _syncService.cancelarPedido(pedido.id!, 'Cancelado pelo usuário', 1);
      await _syncService.forcarSincronizacaoCompleta();
      
      if (_pedidoAtivoService.pedidoAtivoId == pedido.id) {
        _pedidoAtivoService.limparPedidoAtivo();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pedido cancelado! Estoque restaurado.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        _refreshPedidos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cancelar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // 🔥 NOVO: Desbloquear após concluir (sucesso ou erro)
      if (mounted) {
        setState(() => _cancelando = false);
      }
    }
  }

  Future<void> _selecionarPedidoAtivo(Pedido pedido) async {
    final isAtivo = _pedidoAtivoService.pedidoAtivoId == pedido.id;
    
    if (isAtivo) {
      final desativar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Desativar Pedido'),
          content: Text(
            'O Pedido #${pedido.id} está ativo.\n\n'
            'Deseja desativá-lo? O próximo produto criará um novo pedido.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Desativar'),
            ),
          ],
        ),
      );
      
      if (desativar == true) {
        _pedidoAtivoService.limparPedidoAtivo();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pedido desativado.'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {
            _pedidoAtivoId = null;
          });
        }
      }
    } else {
      _pedidoAtivoService.setPedidoAtivo(pedido.id!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pedido #${pedido.id} definido como ativo'),
            backgroundColor: Colors.deepOrange,
            duration: const Duration(seconds: 2),
          ),
        );
        
        setState(() {
          _pedidoAtivoId = pedido.id;
        });
      }
    }
  }

  Future<void> _finalizarPedido(Pedido pedido) async {
    await Navigator.of(context).pushNamed(
      '/finalizar_pedido',
      arguments: pedido.id,
    );
    _refreshPedidos();
  }


  

  // ========== NOVOS MÉTODOS DE EDIÇÃO ==========
  
 Future<void> _alterarQuantidade(Pedido pedido, ItemPedido item, int novaQuantidade) async {
  if (novaQuantidade < 1) {
    await _removerItem(pedido, item);
    return;
  }

  try {
    // Atualizar no banco
    await _syncService.updateQuantidadeItem(item.id!, novaQuantidade);
    await _syncService.forcarSincronizacaoCompleta();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Quantidade atualizada!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
      
      // 🔥 CRÍTICO: Recarregar a lista de pedidos IMEDIATAMENTE
      _refreshPedidos();
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

  Future<void> _editarQuantidadeManual(Pedido pedido, ItemPedido item) async {
    final controller = TextEditingController(text: item.quantidade.toString());
    
    final novaQuantidade = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar Quantidade'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Nova Quantidade',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final valor = int.tryParse(controller.text);
              Navigator.pop(ctx, valor);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (novaQuantidade != null && novaQuantidade > 0) {
      await _alterarQuantidade(pedido, item, novaQuantidade);
    }
  }

  Future<void> _removerItem(Pedido pedido, ItemPedido item) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover Item'),
        content: const Text('Deseja remover este item do pedido?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmado == true) {
      try {
        await _syncService.deleteItemPedido(item.id!);
        await _syncService.forcarSincronizacaoCompleta();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Item removido!'),
              backgroundColor: Colors.green,
            ),
          );
          _refreshPedidos();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao remover: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos Por Finalizar'),
        backgroundColor: Colors.orange,
      ),
      body: FutureBuilder<List<Pedido>>(
        future: _pedidosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }

          final pedidos = snapshot.data ?? [];

          if (pedidos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 100,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Nenhum pedido por finalizar',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Voltar ao Menu'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: pedidos.length,
            itemBuilder: (context, index) {
              final pedido = pedidos[index];
              return _buildPedidoCard(pedido);
            },
          );
        },
      ),
    );
  }

  Widget _buildPedidoCard(Pedido pedido) {
  final totalItens = pedido.itens?.length ?? 0;
  final isAtivo = _pedidoAtivoService.pedidoAtivoId == pedido.id;
  final isExpandido = _pedidoExpandidoId == pedido.id;

  return Card(
    elevation: isAtivo ? 8 : 4,
    margin: const EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: isAtivo 
        ? const BorderSide(color: Colors.teal, width: 2)
        : BorderSide.none,
    ),
    child: Column(
      children: [
        // CABEÇALHO DO PEDIDO (mantido igual)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Pedido #${pedido.id}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isAtivo) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'ATIVO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      pedido.statusPedido.toUpperCase(),
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    DateTime.parse(pedido.dataPedido)
                        .toLocal()
                        .toString()
                        .substring(0, 16),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  const Icon(Icons.shopping_bag, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '$totalItens ${totalItens == 1 ? "item" : "itens"}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'MZN ${pedido.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // BOTÕES DE AÇÃO
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cancelando ? null : () => _selecionarPedidoAtivo(pedido),
                      icon: Icon(isAtivo ? Icons.toggle_on : Icons.toggle_off),
                      label: Text(isAtivo ? 'Desativar' : 'Ativar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAtivo ? Colors.orange : Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cancelando ? null : () {
                        setState(() {
                          _pedidoExpandidoId = isExpandido ? null : pedido.id;
                        });
                      },
                      icon: Icon(isExpandido ? Icons.expand_less : Icons.expand_more),
                      label: Text(isExpandido ? 'Ocultar' : 'Ver Itens'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cancelando ? null : () => _finalizarPedido(pedido),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Finalizar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cancelando ? null : () => _confirmarCancelamento(pedido),
                      icon: _cancelando 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cancel),
                      label: Text(_cancelando ? 'Cancelando...' : 'Cancelar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 🔥 CORREÇÃO CRÍTICA: Renderizar itens com FutureBuilder
        if (isExpandido)
          FutureBuilder<Pedido?>(
            future: _syncService.readPedidoComDetalhes(pedido.id!), // 🔥 RECARREGAR DADOS
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (snapshot.hasError || snapshot.data == null) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  child: const Text(
                    'Erro ao carregar itens',
                    style: TextStyle(color: Colors.red),
                  ),
                );
              }

              final pedidoCompleto = snapshot.data!;
              final itens = pedidoCompleto.itens ?? [];

              if (itens.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  child: const Center(
                    child: Text(
                      'Nenhum item neste pedido',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Column(
                  children: itens.map((item) {
                    return _buildItemPedido(pedidoCompleto, item);
                  }).toList(),
                ),
              );
            },
          ),
      ],
    ),
  );
}

 Widget _buildItemPedido(Pedido pedido, ItemPedido item) {
  final produto = item.produto;
  
  // 🔥 GARANTIR que sempre haverá um nome (nunca será null)
  final nomeProduto = produto?.nome ?? 'Produto #${item.idProduto}';
  
  // 🔥 BUSCAR IMAGEM PRINCIPAL (com fallback seguro)
  ProdutoImagem? imagem;
  if (produto?.imagens != null && produto!.imagens!.isNotEmpty) {
    try {
      imagem = produto.imagens!.firstWhere(
        (img) => img.isPrincipal,
        orElse: () => produto.imagens!.first, // Se não houver principal, usa a primeira
      );
    } catch (e) {
      imagem = null; // Sem imagem disponível
    }
  }

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Colors.grey.shade200),
      ),
    ),
    child: Row(
      children: [
        // 🔥 IMAGEM DO PRODUTO (com validação completa)
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildImagemProduto(imagem, item.idProduto),
        ),
        const SizedBox(width: 12),

        // Info do Produto
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔥 NOME REAL DO PRODUTO
              Text(
                nomeProduto,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'MZN ${item.precoUnitario.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Total: MZN ${item.subtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),

        // Controles de Quantidade
        Column(
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle, size: 20, color: Colors.green),
              onPressed: () => _alterarQuantidade(pedido, item, item.quantidade + 1),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            InkWell(
              onTap: () => _editarQuantidadeManual(pedido, item),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.teal),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${item.quantidade}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle, size: 20, color: Colors.orange),
              onPressed: () => _alterarQuantidade(pedido, item, item.quantidade - 1),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),

        // Botão Remover
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
          onPressed: () => _removerItem(pedido, item),
        ),
      ],
    ),
  );
}

// 🔥 MÉTODO AUXILIAR para renderizar imagem do produto
Widget _buildImagemProduto(ProdutoImagem? imagem, int idProduto) {
  const double tamanho = 60.0;
  
  // Caso 1: Sem imagem disponível
  if (imagem == null || imagem.caminho.isEmpty) {
    return Container(
      width: tamanho,
      height: tamanho,
      color: Colors.grey.shade300,
      child: const Icon(
        Icons.image_not_supported,
        color: Colors.grey,
        size: 30,
      ),
    );
  }

  // Caso 2: URL do Supabase (imagem online)
  if (imagem.caminho.startsWith('http')) {
    return Image.network(
      imagem.caminho,
      width: tamanho,
      height: tamanho,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: tamanho,
          height: tamanho,
          color: Colors.red.shade100,
          child: const Icon(Icons.broken_image, color: Colors.red, size: 30),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: tamanho,
          height: tamanho,
          color: Colors.grey.shade200,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  // Caso 3: Caminho local (arquivo no dispositivo)
  return Image.file(
    File(imagem.caminho),
    width: tamanho,
    height: tamanho,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) {
      return Container(
        width: tamanho,
        height: tamanho,
        color: Colors.orange.shade100,
        child: const Icon(Icons.image_not_supported, color: Colors.orange, size: 30),
      );
    },
  );
} }