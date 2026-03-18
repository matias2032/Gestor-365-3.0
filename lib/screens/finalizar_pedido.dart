// lib/screens/finalizar_pedido.dart (CORRIGIDO)

import '../models/pedido.dart';
import '../services/base_de_dados.dart';
import '../services/pdf_service.dart';
import '../services/pedido_ativo_service.dart'; // 🔥 NOVO IMPORT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/supabase_sync_service.dart';
import '../services/impressora_service.dart';
import 'dart:io';

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
  // final TextEditingController _nomeClienteController = TextEditingController();
  // final TextEditingController _telefoneClienteController = TextEditingController();
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
    // _nomeClienteController.dispose();
    // _telefoneClienteController.dispose();
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
        
        // if (pedido?.telefone != null) {
        //   _telefoneClienteController.text = pedido!.telefone!;
        // }
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

    if (_pedidoAtivoService.pedidoAtivoId == widget.pedidoId) {
      _pedidoAtivoService.limparPedidoAtivo();
    }

    if (mounted) {
      await _mostrarDialogoFatura();
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
  final acao = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.receipt_long, color: Colors.teal),
          SizedBox(width: 10),
          Text('Fatura'),
        ],
      ),
      content: const Text('O que deseja fazer com a fatura?'),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(ctx).pop('pular'),
          icon: const Icon(Icons.skip_next),
          label: const Text('Pular'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(ctx).pop('salvar'),
          icon: const Icon(Icons.save_alt),
          label: const Text('Salvar PDF'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(ctx).pop('imprimir'),
          icon: const Icon(Icons.print),
          label: const Text('Imprimir'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );

  if (!mounted) return;

  switch (acao) {
    case 'imprimir':
      await _gerarEImprimirFatura();
      break;
    case 'salvar':
      await _gerarESalvarFatura();
      break;
    default:
      _voltarParaInicio();
  }
}

Future<void> _gerarEImprimirFatura() async {
  _mostrarLoading('Preparando impressão...');

  try {
    final pedidoAtualizado =
        await _dbService.readPedidoComDetalhes(widget.pedidoId);
    if (pedidoAtualizado == null) throw Exception('Pedido não encontrado');

    final tipoPagamento = _tiposPagamento.firstWhere(
      (t) => t['idtipo_pagamento'] == _tipoPagamentoSelecionado,
    )['tipo_pagamento'] as String;

    if (mounted) Navigator.of(context).pop(); // fecha loading

    // Lê o nome da impressora guardado no ImpressoraService
    final impressoraNome =
        await ImpressoraService.instance.lerImpressoraPadrao();

    if (impressoraNome != null) {
      // ✅ Impressão silenciosa via SumatraPDF
   await _pdfService.imprimirViaSumatra(
  pedido: pedidoAtualizado,
  tipoPagamento: tipoPagamento,
  impressoraNome: impressoraNome,
nomeCliente: null, // _nomeClienteController.text.isEmpty ? null : _nomeClienteController.text,
telefoneCliente: null, // _telefoneClienteController.text.isEmpty ? null : _telefoneClienteController.text,
  // ← sem sumatraPath, é resolvido automaticamente
);
    } else {
      // Fallback: gera e abre o PDF para impressão manual
      final pdfFile = await _pdfService.gerarComprovativo(
        pedido: pedidoAtualizado,
        tipoPagamento: tipoPagamento,
nomeCliente: null,
telefoneCliente: null,
        paperFormat: PaperFormat.thermal80mm,
      );
      await _pdfService.abrirPdf(pdfFile);

      // if (mounted) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     SnackBar(
      //       content: const Text('💡 Configure uma impressora padrão para impressão automática'),
      //       action: SnackBarAction(
      //         label: 'Configurar',
      //         onPressed: () => Navigator.of(context)
      //             .pushNamed('/configuracoes_impressora'),
      //       ),
      //     ),
      //   );
      // }
    }
  } catch (e) {
    if (mounted) Navigator.of(context).pop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao imprimir: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  _voltarParaInicio();
}


// Helper reutilizável para loading
void _mostrarLoading(String mensagem) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(mensagem),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _gerarESalvarFatura() async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
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
    final pedidoAtualizado =
        await _dbService.readPedidoComDetalhes(widget.pedidoId);
    if (pedidoAtualizado == null) throw Exception('Pedido não encontrado');

    final tipoPagamento = _tiposPagamento.firstWhere(
      (t) => t['idtipo_pagamento'] == _tipoPagamentoSelecionado,
    )['tipo_pagamento'] as String;

    final pdfFile = await _pdfService.gerarComprovativo(
      pedido: pedidoAtualizado,
      tipoPagamento: tipoPagamento,
    nomeCliente: null, // _nomeClienteController.text.isEmpty ? null : _nomeClienteController.text,
  telefoneCliente: null, // _telefoneClienteController.text.isEmpty ? null : _telefoneClienteController.text,
      paperFormat: PaperFormat.thermal80mm,
    );

    if (mounted) Navigator.of(context).pop(); // fecha loading

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF guardado: ${pdfFile.path.split(Platform.pathSeparator).last}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } catch (e) {
    if (mounted) Navigator.of(context).pop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  _voltarParaInicio();
}

 void _voltarParaInicio() {
  if (!mounted) return;
  // 🔥 Navega para /menu explicitamente, removendo apenas
  // as rotas acima dele — nunca chega ao login
  Navigator.of(context).pushNamedAndRemoveUntil(
    '/menu',
    (route) => false,
  );
}

bool get _podeFinalizar {
  if (_isFinalizando) return false;
  if (_tipoPagamentoSelecionado == null) return false;
  
  // Se for dinheiro, valida se o valor inserido é suficiente
  if (_mostrarCampoValor) {
    final valorRecebido = double.tryParse(_valorRecebidoController.text) ?? 0.0;
    return valorRecebido >= (_pedido?.total ?? 0.0);
  }
  
  return true; // Para outros métodos, o botão fica ativo após selecionar
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

            // Card(
            //   child: Padding(
            //     padding: const EdgeInsets.all(16),
            //     child: Column(
            //       crossAxisAlignment: CrossAxisAlignment.start,
            //       children: [
            //         Row(
            //           children: [
            //             Icon(Icons.person_outline, color: Colors.grey.shade600),
            //             const SizedBox(width: 8),
            //             const Text(
            //               'Informações do Cliente (Opcional)',
            //               style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            //             ),
            //           ],
            //         ),
            //         const SizedBox(height: 12),
            //         TextField(
            //           controller: _nomeClienteController,
            //           decoration: const InputDecoration(
            //             labelText: 'Nome do Cliente',
            //             border: OutlineInputBorder(),
            //             prefixIcon: Icon(Icons.person),
            //           ),
            //         ),
            //         const SizedBox(height: 12),
            //         TextField(
            //           controller: _telefoneClienteController,
            //           keyboardType: TextInputType.phone,
            //           decoration: const InputDecoration(
            //             labelText: 'Telefone',
            //             border: OutlineInputBorder(),
            //             prefixIcon: Icon(Icons.phone),
            //           ),
            //         ),
            //       ],
            //     ),
            //   ),
            // ),
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
  
  // 🔥 NOVO: Alerta visual amigável
  Builder(
    builder: (context) {
      final valorRecebido = double.tryParse(_valorRecebidoController.text) ?? 0.0;
      final insuficiente = valorRecebido > 0 && valorRecebido < (_pedido?.total ?? 0.0);
      
      return AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: insuficiente ? 1.0 : 0.0,
        child: Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 4.0),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Text(
                'O valor inserido ainda é menor que o total.',
                style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    },
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
                onPressed: _podeFinalizar ? _finalizarPedido : null,
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