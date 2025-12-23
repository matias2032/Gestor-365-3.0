// lib/screens/pedidos_por_finalizar.dart (COM CONTADOR SINCRONIZADO)

import 'package:flutter/material.dart';
import 'dart:async';
import '../models/pedido.dart';
import '../services/base_de_dados.dart';
import '../services/pedido_ativo_service.dart';
import '../services/pedido_contador_service.dart'; // 🔥 NOVO IMPORT
import '../services/supabase_sync_service.dart';

class PedidosPorFinalizarScreen extends StatefulWidget {
  const PedidosPorFinalizarScreen({super.key});

  @override
  State<PedidosPorFinalizarScreen> createState() => _PedidosPorFinalizarScreenState();
}

class _PedidosPorFinalizarScreenState extends State<PedidosPorFinalizarScreen> {
  final DatabaseService _dbService = DatabaseService.instance;
  final PedidoAtivoService _pedidoAtivoService = PedidoAtivoService.instance;
  final PedidoContadorService _contadorService = PedidoContadorService.instance; // 🔥 NOVO
      final SupabaseSyncService _syncService = SupabaseSyncService.instance;
  
  late Future<List<Pedido>> _pedidosFuture;
  int? _pedidoAtivoId;

  @override
  void initState() {
    super.initState();
    _pedidoAtivoId = _pedidoAtivoService.pedidoAtivoId;
    _pedidosFuture = _carregarPedidos();
  }

  Future<List<Pedido>> _carregarPedidos() async {
    final pedidos = await _dbService.readPedidosPorFinalizar(1);
    
    // 🔥 ATUALIZA O CONTADOR GLOBAL
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
    try {
      await _syncService.cancelarPedido(pedido.id!, 'Cancelado pelo usuário', 1);
      
      if (_pedidoAtivoService.pedidoAtivoId == pedido.id) {
        _pedidoAtivoService.limparPedidoAtivo();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pedido cancelado com sucesso! Estoque restaurado.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // 🔥 REFRESH ATUALIZA O CONTADOR AUTOMATICAMENTE
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
            'O Pedido #${pedido.id} está atualmente ativo.\n\n'
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
              content: Text('Pedido desativado. Próximo produto criará novo pedido.'),
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
            content: Text('Pedido #${pedido.id} selecionado como ativo'),
            backgroundColor: Colors.deepOrange,
            duration: const Duration(seconds: 2),
          ),
        );
        
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _detalhespedido(Pedido pedido) async {
    await Navigator.of(context).pushNamed(
      '/detalhes_pedido',
      arguments: pedido.id,
    );
    _refreshPedidos();
  }

  Future<void> _finalizarPedido(Pedido pedido) async {
    await Navigator.of(context).pushNamed(
      '/finalizar_pedido',
      arguments: pedido.id,
    );
    _refreshPedidos();
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
              final totalItens = pedido.itens?.length ?? 0;
              final isAtivo = _pedidoAtivoService.pedidoAtivoId == pedido.id;

              return Card(
                elevation: isAtivo ? 8 : 4,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isAtivo 
                    ? const BorderSide(color: Colors.teal, width: 2)
                    : BorderSide.none,
                ),
                child: Padding(
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

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _selecionarPedidoAtivo(pedido),
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
                              onPressed: () => _detalhespedido(pedido),
                              icon: const Icon(Icons.visibility),
                              label: const Text('Detalhes'),
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
                              onPressed: () => _finalizarPedido(pedido),
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
                              onPressed: () => _confirmarCancelamento(pedido),
                              icon: const Icon(Icons.cancel),
                              label: const Text('Cancelar'),
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
              );
            },
          );
        },
      ),
    );
  }
}