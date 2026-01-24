// lib/screens/movimentos_estoque.dart
// TELA SOMENTE PARA VISUALIZAÇÃO DOS MOVIMENTOS DE ESTOQUE

import 'package:flutter/material.dart';
import 'dart:async';
import '../services/base_de_dados.dart';
import '../services/servico_movimento_estoque.dart';
import '../models/movimento_estoque.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/conectividade_indicator.dart';


class MovimentosEstoqueScreen extends StatefulWidget {
  const MovimentosEstoqueScreen({super.key});

  @override
  State<MovimentosEstoqueScreen> createState() => _MovimentosEstoqueScreenState();
}

class _MovimentosEstoqueScreenState extends State<MovimentosEstoqueScreen> {
  final DatabaseService _dbService = DatabaseService.instance;
  final ServicoMovimentoEstoque _movimentoService =
      ServicoMovimentoEstoque.instance;

  List<MovimentoEstoque> _historicoMovimentos = [];
  bool _isLoading = true;

  StreamSubscription<MovimentoEstoque>? _movimentoSubscription;
  StreamSubscription<void>? _estoqueSubscription;

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
    _configurarListeners();
  }

  @override
  void dispose() {
    _movimentoSubscription?.cancel();
    _estoqueSubscription?.cancel();
    super.dispose();
  }

  void _configurarListeners() {
    // Listener apenas para ATUALIZAR a visualização
    _movimentoSubscription =
        _movimentoService.movimentoStream.listen((_) {
      _carregarHistorico();
    });

    _estoqueSubscription = _dbService.estoqueStream.listen((_) {
      _carregarHistorico();
    });
  }

  Future<void> _carregarHistorico() async {
    setState(() => _isLoading = true);
    try {
      final historico = await _movimentoService.buscarHistorico(limit: 100);
      if (mounted) {
        setState(() => _historicoMovimentos = historico);
      }
    } catch (e) {
      _mostrarErro('Erro ao carregar histórico: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(mensagem)),
          ],
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimentos de Estoque'),
        backgroundColor: Colors.deepOrange,
        actions: [
          const ConectividadeIndicator(),
          ThemeToggleWidget(showLabel: false),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarHistorico,
            tooltip: 'Recarregar',
          ),
        ],
      ),
      drawer: const AppSidebar(currentRoute: '/movimentos_estoque'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildHistorico(),
    );
  }

  Widget _buildHistorico() {
    if (_historicoMovimentos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Nenhum movimento registrado',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _historicoMovimentos.length,
      itemBuilder: (context, index) {
        final movimento = _historicoMovimentos[index];
        final isAcrescimo =
            movimento.tipoMovimento == TipoMovimento.acrescimo;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isAcrescimo ? Colors.green : Colors.orange,
              child: Icon(
                isAcrescimo ? Icons.add : Icons.remove,
                color: Colors.white,
              ),
            ),
            title: Text(
              movimento.nomeProduto ?? 'Produto #${movimento.idProduto}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(movimento.descricaoMovimento),
                Text(
                  '${movimento.quantidadeAnterior} → ${movimento.quantidadeNova} unidades',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Por: ${movimento.nomeUsuario ?? "Usuário #${movimento.idUsuario}"}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  DateTime.parse(movimento.dataMovimento)
                      .toLocal()
                      .toString()
                      .substring(0, 16),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                  ),
                ),
                if (movimento.motivo != null && movimento.motivo!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Motivo: ${movimento.motivo}',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
