// lib/screens/finalizar_pedido.dart (CORRIGIDO)

import '../models/pedido.dart';
import '../services/base_de_dados.dart';
import '../services/pdf_service.dart';
import '../services/pedido_ativo_service.dart'; // 🔥 NOVO IMPORT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../services/supabase_sync_service.dart';

class FinalizarPedidoScreen extends StatefulWidget {
  final int pedidoId;

  const FinalizarPedidoScreen({super.key, required this.pedidoId});

  @override
  State<FinalizarPedidoScreen> createState() => _FinalizarPedidoScreenState();
}

class _FinalizarPedidoScreenState extends State<FinalizarPedidoScreen> {
  final DatabaseService _dbService = DatabaseService.instance;
  final PdfService _pdfService = PdfService.instance;
  final PedidoAtivoService _pedidoAtivoService = PedidoAtivoService.instance; // 🔥 NOVO
  
  final TextEditingController _valorRecebidoController = TextEditingController();
  final TextEditingController _nomeClienteController = TextEditingController();
  final TextEditingController _telefoneClienteController = TextEditingController();
    final SupabaseSyncService _syncService = SupabaseSyncService.instance;

  Pedido? _pedido;
  List<Map<String, dynamic>> _tiposPagamento = [];
  int? _tipoPagamentoSelecionado;
  bool _isLoading = true;
  bool _mostrarCampoValor = false;
  double _troco = 0.0;
  bool _isFinalizando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _valorRecebidoController.dispose();
    _nomeClienteController.dispose();
    _telefoneClienteController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    try {
      final pedido = await _dbService.readPedidoComDetalhes(widget.pedidoId);
      final tipos = await _dbService.readTiposPagamento();
      
      setState(() {
        _pedido = pedido;
        _tiposPagamento = tipos;
        _isLoading = false;
        
        if (pedido?.telefone != null) {
          _telefoneClienteController.text = pedido!.telefone!;
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onTipoPagamentoChanged(int? valor) {
    setState(() {
      _tipoPagamentoSelecionado = valor;
      _mostrarCampoValor = _tiposPagamento.firstWhere(
        (t) => t['idtipo_pagamento'] == valor,
        orElse: () => {'tipo_pagamento': ''},
      )['tipo_pagamento']?.toString().toLowerCase().contains('dinheiro') ?? false;
      
      if (!_mostrarCampoValor) {
        _valorRecebidoController.clear();
        _troco = 0.0;
      }
    });
  }

  void _calcularTroco() {
    if (_pedido == null) return;
    
    final valorRecebido = double.tryParse(_valorRecebidoController.text) ?? 0.0;
    setState(() {
      _troco = valorRecebido >= _pedido!.total ? valorRecebido - _pedido!.total : 0.0;
    });
  }

  Future<void> _finalizarPedido() async {
    if (_tipoPagamentoSelecionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o método de pagamento')),
      );
      return;
    }

    if (_mostrarCampoValor) {
      final valorRecebido = double.tryParse(_valorRecebidoController.text) ?? 0.0;
      if (valorRecebido < _pedido!.total) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Valor recebido insuficiente')),
        );
        return;
      }
    }

    setState(() => _isFinalizando = true);

    try {
      await _syncService.finalizarPedido(
        widget.pedidoId,
        _tipoPagamentoSelecionado!,
        valorPago: double.tryParse(_valorRecebidoController.text),
        troco: _troco,
      );
   


      // 🔥 DESATIVAR PEDIDO AUTOMATICAMENTE APÓS FINALIZAR
      if (_pedidoAtivoService.pedidoAtivoId == widget.pedidoId) {
        _pedidoAtivoService.limparPedidoAtivo();
      }

      // if (mounted) {
      //   await _mostrarDialogoFatura();
      // }


// 🔥 NOVO: Redirecionar diretamente para o menu
if (mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('✅ Pedido finalizado com sucesso!'),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 2),
    ),
  );
  
  // Redirecionar para o menu
  Navigator.of(context).pushNamedAndRemoveUntil('/menu', (route) => false);
}

    } catch (e) {
      setState(() => _isFinalizando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _mostrarDialogoFatura() async {
    final gerarFatura = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: Colors.teal, size: 30),
            const SizedBox(width: 12),
            const Text('Gerar Fatura?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Deseja gerar uma fatura em PDF para este pedido?',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'A fatura conterá todos os detalhes do pedido e poderá ser impressa.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(ctx).pop(false),
            icon: const Icon(Icons.close),
            label: const Text('Não'),
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check_circle),
            label: const Text('Sim, Gerar Fatura'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (gerarFatura == true && mounted) {
      await _gerarFatura();
    } else {
      _voltarParaInicio();
    }
  }

  Future<void> _gerarFatura() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Gerando fatura...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final pedidoAtualizado = await _dbService.readPedidoComDetalhes(widget.pedidoId);
      
      if (pedidoAtualizado == null) throw Exception('Pedido não encontrado');

      final tipoPagamento = _tiposPagamento.firstWhere(
        (t) => t['idtipo_pagamento'] == _tipoPagamentoSelecionado,
      )['tipo_pagamento'] as String;

      final pdfFile = await _pdfService.gerarFatura(
        pedido: pedidoAtualizado,
        tipoPagamento: tipoPagamento,
        nomeCliente: _nomeClienteController.text.isEmpty 
            ? null 
            : _nomeClienteController.text,
        telefoneCliente: _telefoneClienteController.text.isEmpty 
            ? null 
            : _telefoneClienteController.text,
      );

      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        await _mostrarDialogoSucesso(pdfFile);
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar fatura: $e'),
            backgroundColor: Colors.red,
          ),
        );
        _voltarParaInicio();
      }
    }
  }

  Future<void> _mostrarDialogoSucesso(File pdfFile) async {
    final acao = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 30),
            const SizedBox(width: 12),
            const Text('Fatura Gerada!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A fatura foi gerada com sucesso!',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder, color: Colors.teal, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pdfFile.path.split('/').last,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'O PDF foi salvo em: ${pdfFile.parent.path}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('fechar'),
            child: const Text('Fechar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop('abrir'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Abrir PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (acao == 'abrir') {
      try {
        // 🔥 CORREÇÃO: Usar método mais robusto para abrir PDF
        await _pdfService.abrirPdf(pdfFile);
      } catch (e) {
        if (mounted) {
          // 🔥 FALLBACK: Se falhar, mostrar caminho para o usuário
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Atenção'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Não foi possível abrir o PDF automaticamente.'),
                  const SizedBox(height: 12),
                  const Text('Arquivo salvo em:', 
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    pdfFile.path,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Use um gerenciador de arquivos para abrir o PDF.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    }

    _voltarParaInicio();
  }

  void _voltarParaInicio() {
    // if (mounted) {
    //   Navigator.of(context).popUntil((route) => route.isFirst);
    // }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Carregando...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_pedido == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Erro')),
        body: const Center(child: Text('Pedido não encontrado')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Finalizar Pedido #${_pedido!.id}'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resumo do Pedido',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total de Itens:', style: TextStyle(fontSize: 16)),
                        Text(
                          '${_pedido!.itens?.length ?? 0}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_outline, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        const Text(
                          'Informações do Cliente (Opcional)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nomeClienteController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do Cliente',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _telefoneClienteController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefone',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Método de Pagamento',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _tipoPagamentoSelecionado,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payment),
              ),
              hint: const Text('Selecione o método'),
              items: _tiposPagamento.map((tipo) {
                return DropdownMenuItem<int>(
                  value: tipo['idtipo_pagamento'] as int,
                  child: Text(tipo['tipo_pagamento'] as String),
                );
              }).toList(),
              onChanged: _onTipoPagamentoChanged,
            ),

            if (_mostrarCampoValor) ...[
              const SizedBox(height: 20),
              TextField(
                controller: _valorRecebidoController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                decoration: const InputDecoration(
                  labelText: 'Valor Recebido',
                  prefixText: 'MZN ',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _calcularTroco(),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Troco:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      'MZN ${_troco.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isFinalizando ? null : _finalizarPedido,
                icon: _isFinalizando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(
                  _isFinalizando ? 'Finalizando...' : 'Confirmar Pagamento',
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}