// lib/screens/historico_pedidos.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pedido.dart';
import '../services/base_de_dados.dart';
import '../services/pdf_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/theme_toggle_widget.dart';
import 'dart:io';

enum PeriodoFiltro {
  hoje,
  sete_dias,
  um_mes,
  tres_meses,
  seis_meses,
  um_ano,
}

class HistoricoPedidosScreen extends StatefulWidget {
  const HistoricoPedidosScreen({super.key});

  @override
  State<HistoricoPedidosScreen> createState() => _HistoricoPedidosScreenState();
}

class _HistoricoPedidosScreenState extends State<HistoricoPedidosScreen> {
  late Future<List<Pedido>> _pedidosFuture;
  PeriodoFiltro _filtroAtual = PeriodoFiltro.hoje;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _pedidosFuture = _loadPedidos();
  }

  Future<List<Pedido>> _loadPedidos() async {
    final db = DatabaseService.instance;
    final dataInicio = _getDataInicio(_filtroAtual);
    
    final result = await db.database;
    final pedidosMaps = await result.rawQuery('''
      SELECT p.*, u.nome || ' ' || u.apelido as nome_usuario
      FROM pedido p
      LEFT JOIN usuario u ON p.id_usuario = u.id_usuario
      WHERE p.status_pedido = 'finalizado'
        AND p.data_finalizacao >= ?
      ORDER BY p.data_finalizacao DESC
    ''', [dataInicio]);

    final List<Pedido> pedidos = [];
    for (var pedidoMap in pedidosMaps) {
      final pedido = Pedido.fromMap(pedidoMap);
      final itens = await _loadItensPedido(pedido.id!);
      pedidos.add(pedido.copyWith(itens: itens));
    }

    return pedidos;
  }

  Future<List<ItemPedido>> _loadItensPedido(int idPedido) async {
    final db = DatabaseService.instance;
    final result = await db.database;
    
    final itensMaps = await result.rawQuery('''
      SELECT ip.*, p.nome_produto
      FROM item_pedido ip
      INNER JOIN produto p ON ip.id_produto = p.id_produto
      WHERE ip.id_pedido = ?
    ''', [idPedido]);

    return itensMaps.map((map) => ItemPedido.fromMap(map)).toList();
  }

  String _getDataInicio(PeriodoFiltro filtro) {
    final agora = DateTime.now();
    DateTime dataInicio;

    switch (filtro) {
      case PeriodoFiltro.hoje:
        dataInicio = DateTime(agora.year, agora.month, agora.day);
        break;
      case PeriodoFiltro.sete_dias:
        dataInicio = agora.subtract(const Duration(days: 7));
        break;
      case PeriodoFiltro.um_mes:
        dataInicio = DateTime(agora.year, agora.month - 1, agora.day);
        break;
      case PeriodoFiltro.tres_meses:
        dataInicio = DateTime(agora.year, agora.month - 3, agora.day);
        break;
      case PeriodoFiltro.seis_meses:
        dataInicio = DateTime(agora.year, agora.month - 6, agora.day);
        break;
      case PeriodoFiltro.um_ano:
        dataInicio = DateTime(agora.year - 1, agora.month, agora.day);
        break;
    }

    return dataInicio.toIso8601String();
  }

  String _getFiltroLabel(PeriodoFiltro filtro) {
    switch (filtro) {
      case PeriodoFiltro.hoje:
        return 'Hoje';
      case PeriodoFiltro.sete_dias:
        return 'Últimos 7 dias';
      case PeriodoFiltro.um_mes:
        return '1 Mês';
      case PeriodoFiltro.tres_meses:
        return '3 Meses';
      case PeriodoFiltro.seis_meses:
        return '6 Meses';
      case PeriodoFiltro.um_ano:
        return '1 Ano';
    }
  }

  Future<void> _gerarFatura(Pedido pedido) async {
    setState(() => _isGeneratingPdf = true);

    try {
      final db = DatabaseService.instance;
      final tiposPagamento = await db.readTiposPagamento();
      final tipoPagamento = tiposPagamento.firstWhere(
        (tp) => tp['idtipo_pagamento'] == pedido.idTipoPagamento,
        orElse: () => {'tipo_pagamento': 'Desconhecido'},
      )['tipo_pagamento'] as String;

      final file = await PdfService.instance.gerarFatura(
        pedido: pedido,
        tipoPagamento: tipoPagamento,
        nomeCliente: pedido.nomeUsuario,
        telefoneCliente: pedido.telefone,
      );

      await PdfService.instance.abrirPdf(file);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fatura gerada: ${file.path}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar fatura: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _imprimirTodosPedidos(List<Pedido> pedidos) async {
    if (pedidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum pedido para imprimir'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);

    try {
      // Aqui você pode implementar a geração de um relatório consolidado
      // Por enquanto, vou mostrar um diálogo informativo
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Relatório de Pedidos'),
          content: Text(
            'Total de pedidos: ${pedidos.length}\n'
            'Período: ${_getFiltroLabel(_filtroAtual)}\n'
            'Valor total: MZN ${pedidos.fold<double>(0, (sum, p) => sum + p.total).toStringAsFixed(2)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } finally {
      setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Histórico (${_getFiltroLabel(_filtroAtual)})'),
        backgroundColor: Colors.deepOrange,
        actions: [
          ThemeToggleWidget(showLabel: false),
          PopupMenuButton<PeriodoFiltro>(
            icon: const Icon(Icons.filter_list),
            onSelected: (PeriodoFiltro newFilter) {
              setState(() {
                _filtroAtual = newFilter;
                _pedidosFuture = _loadPedidos();
              });
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<PeriodoFiltro>>[
              const PopupMenuItem(
                value: PeriodoFiltro.hoje,
                child: Text('Hoje'),
              ),
              const PopupMenuItem(
                value: PeriodoFiltro.sete_dias,
                child: Text('Últimos 7 dias'),
              ),
              const PopupMenuItem(
                value: PeriodoFiltro.um_mes,
                child: Text('1 Mês'),
              ),
              const PopupMenuItem(
                value: PeriodoFiltro.tres_meses,
                child: Text('3 Meses'),
              ),
              const PopupMenuItem(
                value: PeriodoFiltro.seis_meses,
                child: Text('6 Meses'),
              ),
              const PopupMenuItem(
                value: PeriodoFiltro.um_ano,
                child: Text('1 Ano'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _pedidosFuture = _loadPedidos();
              });
            },
          ),
        ],
      ),
      drawer: const AppSidebar(currentRoute: '/historico_pedidos'),
      body: FutureBuilder<List<Pedido>>(
        future: _pedidosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Erro: ${snapshot.error}'),
            );
          }

          final pedidos = snapshot.data ?? [];

          if (pedidos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum pedido finalizado em ${_getFiltroLabel(_filtroAtual).toLowerCase()}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.deepOrange.shade50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total: ${pedidos.length} pedidos',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isGeneratingPdf
                          ? null
                          : () => _imprimirTodosPedidos(pedidos),
                      icon: const Icon(Icons.print),
                      label: const Text('Imprimir Todos'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: pedidos.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final pedido = pedidos[index];
                    return _buildPedidoCard(pedido);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPedidoCard(Pedido pedido) {
    final dataFormatada = pedido.dataFinalizacao != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(pedido.dataFinalizacao!))
        : 'N/A';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green,
          child: Text(
            '#${pedido.id}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          pedido.nomeUsuario ?? 'Cliente',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Finalizado em: $dataFormatada\nTotal: MZN ${pedido.total.toStringAsFixed(2)}',
        ),
        trailing: IconButton(
          icon: _isGeneratingPdf
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf, color: Colors.red),
          onPressed: _isGeneratingPdf ? null : () => _gerarFatura(pedido),
          tooltip: 'Gerar Fatura',
        ),
        children: [
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Itens do Pedido:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                ...?pedido.itens?.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${item.quantidade}x ${item.produto?.nome ?? "Produto"}',
                            ),
                          ),
                          Text(
                            'MZN ${item.subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )),
                const Divider(),
                if (pedido.telefone != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.phone, size: 16),
                        const SizedBox(width: 8),
                        Text(pedido.telefone!),
                      ],
                    ),
                  ),
                if (pedido.bairro != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, size: 16),
                        const SizedBox(width: 8),
                        Text(pedido.bairro!),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}