// lib/screens/detalhes_pedido.dart

import 'package:flutter/material.dart';
import 'dart:io';
import '../models/pedido.dart';
import '../services/base_de_dados.dart';
import '../models/produto_imagem.dart';
import '../services/supabase_sync_service.dart';

class DetalhesPedidoScreen extends StatefulWidget {
  final int pedidoId;

  const DetalhesPedidoScreen({super.key, required this.pedidoId});

  @override
  State<DetalhesPedidoScreen> createState() => _DetalhesPedidoScreenState();
}

class _DetalhesPedidoScreenState extends State<DetalhesPedidoScreen> {
  final DatabaseService _dbService = DatabaseService.instance;
final _syncService = SupabaseSyncService.instance;
  Pedido? _pedido;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarPedido();
  }

  Future<void> _carregarPedido() async {
    try {
      final pedido = await _dbService.readPedidoComDetalhes(widget.pedidoId);
      if (mounted) {
        setState(() {
          _pedido = pedido;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar: $e')),
        );
      }
    }
  }

  Future<void> _alterarQuantidade(ItemPedido item, int novaQuantidade) async {
    if (novaQuantidade < 1) return;

    try {
      await _syncService.updateQuantidadeItem(item.id!, novaQuantidade);
      await _carregarPedido();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quantidade atualizada!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removerItem(ItemPedido item) async {
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
        await _carregarPedido();
        
        // Se não houver mais itens, voltar
        if (_pedido?.itens?.isEmpty ?? true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pedido removido (sem itens)')),
            );
            Navigator.of(context).pop();
          }
          return;
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Item removido!'),
              backgroundColor: Colors.green,
            ),
          );
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
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Carregando...'),
          backgroundColor: Colors.blue,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_pedido == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Erro'),
          backgroundColor: Colors.red,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 80, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Pedido não encontrado',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Voltar'),
              ),
            ],
          ),
        ),
      );
    }

    final itens = _pedido!.itens ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${_pedido!.id}'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Lista de Itens
          Expanded(
            child: itens.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 80,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Nenhum item neste pedido',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: itens.length,
                    itemBuilder: (context, index) {
                      final item = itens[index];
                      final produto = item.produto;
                      final imagem = produto?.imagens?.firstWhere(
                        (img) => img.isPrincipal,
                        orElse: () => ProdutoImagem(
                          idProduto: produto.id!,
                          caminho: '',
                          isPrincipal: false,
                        ),
                      );

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              // Imagem
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: imagem != null && imagem.caminho.isNotEmpty
                                    ? Image.file(
                                        File(imagem.caminho),
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        width: 80,
                                        height: 80,
                                        color: Colors.grey.shade300,
                                        child: const Icon(
                                          Icons.image_not_supported,
                                          color: Colors.grey,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),

                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      produto?.nome ?? 'Produto',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'MZN ${item.precoUnitario.toStringAsFixed(2)} x ${item.quantidade}',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Subtotal: MZN ${item.subtotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Controles
                              Column(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.add_circle, color: Colors.green),
                                    onPressed: () => _alterarQuantidade(item, item.quantidade + 1),
                                    tooltip: 'Aumentar quantidade',
                                  ),
                                  Text(
                                    '${item.quantidade}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle, color: Colors.orange),
                                    onPressed: () => _alterarQuantidade(item, item.quantidade - 1),
                                    tooltip: 'Diminuir quantidade',
                                  ),
                                ],
                              ),

                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _removerItem(item),
                                tooltip: 'Remover item',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Rodapé com Total
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total:',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'MZN ${_pedido!.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}