// lib/screens/detalhes_produto.dart

import 'package:flutter/material.dart';
import '../models/produto.dart';
import '../models/pedido.dart';
import '../services/base_de_dados.dart';
import '../services/pedido_ativo_service.dart';
import '../models/produto_imagem.dart';
import '../services/supabase_sync_service.dart';
import '../services/sessao_service.dart';
import '../widgets/cached_produto_image.dart';
import 'dart:async';


class DetalhesProdutoScreen extends StatefulWidget {
  final int produtoId;

  const DetalhesProdutoScreen({super.key, required this.produtoId});

  @override
  State<DetalhesProdutoScreen> createState() => _DetalhesProdutoScreenState();
}

class _DetalhesProdutoScreenState extends State<DetalhesProdutoScreen> {
  final DatabaseService _dbService = DatabaseService.instance;
  final PedidoAtivoService _pedidoAtivoService = PedidoAtivoService.instance;
    final SupabaseSyncService _syncService = SupabaseSyncService.instance;
  
  Produto? _produto;
  bool _isLoading = true;
  int _quantidade = 1;
  bool _isAdicionando = false;

  @override
  void initState() {
    super.initState();
    _carregarProduto();
  }

  Future<void> _carregarProduto() async {
    try {
      final produto = await _dbService.readProdutoWithDetailsById(widget.produtoId);
      if (mounted) {
        setState(() {
          _produto = produto;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar produto: $e')),
        );
      }
    }
  }

  void _incrementarQuantidade() {
    if (_produto == null) return;
    
    final estoqueDisponivel = _produto!.quantidadeEstoque ?? 0;
    
    if (_quantidade >= estoqueDisponivel) {
      _mostrarPopup(
        'Limite de Estoque',
        'A quantidade máxima disponível é $estoqueDisponivel unidades.',
        Icons.warning,
        Colors.orange,
      );
      return;
    }
    
    setState(() {
      _quantidade++;
    });
  }

  void _decrementarQuantidade() {
    if (_quantidade > 1) {
      setState(() {
        _quantidade--;
      });
    }
  }



  

double _calcularTotal() {
  if (_produto == null) return 0.0;

  // 🔥 VERIFICAR SE CATEGORIA PROMOCIONAL ESTÁ ATIVA
  final temCategoriaPromocao = _produto!.categoriasAssociadas
      ?.any((c) => c.nome == 'Promoções da Semana') ?? false;
  
  // 🔥 SÓ USA PREÇO PROMOCIONAL SE TIVER A CATEGORIA
  final preco = (temCategoriaPromocao && _produto!.precoPromocional != null)
      ? _produto!.precoPromocional!
      : _produto!.preco;

  return preco * _quantidade;
}




// 🔥 SUBSTITUIR o bloco try-catch completo:

Future<void> _adicionarAoPedido() async {
  if (_produto == null || _isAdicionando) return;
  
  setState(() => _isAdicionando = true);
  
  try {
    final usuario = SessaoService.instance.usuarioAtual;
    if (usuario == null) {
      throw Exception('Usuário não está logado');
    }
    
    final idUsuario = usuario.id!;
    int pedidoId;
    
    if (_pedidoAtivoService.temPedidoAtivo) {
      pedidoId = _pedidoAtivoService.pedidoAtivoId!;
      
      await _syncService.adicionarItemAoPedido(
        pedidoId,
        _produto!.id!,
        _quantidade,
      );
      
   
      
      if (mounted) {
        _mostrarPopup(
          'Sucesso!',
          'Produto adicionado ao Pedido #$pedidoId.',
          Icons.check_circle,
          Colors.green,
          aoFechar: () => Navigator.of(context).pop(),
        );
      }
    } else {
      final item = ItemPedido(
        idPedido: 0,
        idProduto: _produto!.id!,
        quantidade: _quantidade,
        precoUnitario: _produto!.preco,
        subtotal: _calcularTotal(),
      );
      
      final pedido = Pedido(
        idUsuario: idUsuario,
        idTipoPagamento: 1,
        dataPedido: DateTime.now().toIso8601String(),
        total: _calcularTotal(),
        statusPedido: 'por finalizar',
      );
      
      pedidoId = await _syncService.createPedido(pedido, [item]);

      
      _pedidoAtivoService.setPedidoAtivo(pedidoId);
      
      if (mounted) {
        // 🔥 NOVO: Verificar se foi criado offline
        final modoOffline = !_syncService.isOnline;
        final icone = modoOffline ? Icons.cloud_off : Icons.check_circle;
        final cor = modoOffline ? Colors.orange : Colors.green;
        final mensagem = modoOffline
            ? 'Pedido criado localmente (#$pedidoId).\nSerá sincronizado quando houver conexão estável.'
            : 'Novo pedido criado (#$pedidoId) e definido como ativo.';
        
        _mostrarPopup(
          'Sucesso!',
          mensagem,
          icone,
          cor,
          aoFechar: () => Navigator.of(context).pop(),
        );
      }
    }
  } on TimeoutException {
    // 🔥 NOVO: Tratamento específico para timeout
    if (mounted) {
      _mostrarPopup(
        'Conexão Instável',
        'Não foi possível criar o pedido devido à conexão instável.\n\n'
        'Tente novamente quando a conexão estiver estável.',
        Icons.wifi_off,
        Colors.orange,
      );
    }
  } catch (e) {
    if (mounted) {
      final mensagem = e.toString().contains('Estoque insuficiente')
          ? e.toString()
          : 'Falha ao adicionar produto: $e\n\nVerifique sua conexão e tente novamente.';
      
      _mostrarPopup(
        'Erro',
        mensagem,
        Icons.error,
        Colors.red,
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isAdicionando = false);
    }
  }
}

  void _mostrarPopup(String titulo, String mensagem, IconData icone, Color cor, {VoidCallback? aoFechar}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icone, color: cor, size: 30),
            const SizedBox(width: 12),
            Flexible(child: Text(titulo)),
          ],
        ),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (aoFechar != null) aoFechar();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Carregando...'),
          backgroundColor: Colors.teal,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_produto == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Erro'),
          backgroundColor: Colors.red,
        ),
        body: const Center(child: Text('Produto não encontrado.')),
      );
    }

    final imagemPrincipal = _produto!.imagens?.firstWhere(
      (img) => img.isPrincipal,
      orElse: () => ProdutoImagem(
        idProduto: _produto!.id!,
        caminho: '',
        isPrincipal: false,
      ),
    );
    
    final caminhoImagem = imagemPrincipal?.caminho ?? '';
    final estoque = _produto!.quantidadeEstoque ?? 0;
    final estoqueEsgotado = estoque <= 0;
    
    // Info sobre pedido ativo
    final temPedidoAtivo = _pedidoAtivoService.temPedidoAtivo;
    final pedidoAtivoId = _pedidoAtivoService.pedidoAtivoId;

    return Scaffold(
      appBar: AppBar(
        title: Text(_produto!.nome),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Pedido Ativo (se houver)
            if (temPedidoAtivo)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.teal.shade50,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Será adicionado ao Pedido #$pedidoAtivoId (ativo)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            // Imagem Grande
   Hero(
  tag: 'produto_${_produto!.id}',
  child: CachedProdutoImage(
    imagePath: caminhoImagem,
    height: 300,
    width: double.infinity,
    fit: BoxFit.cover,
    placeholder: Container(
      height: 300,
      color: Colors.grey.shade200,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    ),
    errorWidget: Container(
      height: 300,
      color: Colors.grey.shade300,
      child: const Icon(
        Icons.image_not_supported,
        size: 100,
        color: Colors.grey,
      ),
    ),
  ),
),
            // Conteúdo
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome
                  Text(
                    _produto!.nome,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Categorias
                  if (_produto!.categoriasAssociadas != null && 
                      _produto!.categoriasAssociadas!.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: _produto!.categoriasAssociadas!.map((cat) {
                        return Chip(
                          label: Text(cat.nome),
                          backgroundColor: Colors.teal.shade50,
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  
                  // Descrição
                  if (_produto!.descricao != null && _produto!.descricao!.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Descrição',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _produto!.descricao!,
                          style: const TextStyle(fontSize: 16, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  
      // Preço
     Row(
  children: [
    const Text('Preço: ', style: TextStyle(fontSize: 18)),
    
    // 🔥 VERIFICAÇÃO CONDICIONAL
    if (_produto!.categoriasAssociadas?.any((c) => c.nome == 'Promoções da Semana') == true &&
        _produto!.precoPromocional != null) ...[
      Text(
        'MZN ${_produto!.preco.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 20,
          color: Colors.grey,
          decoration: TextDecoration.lineThrough,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        'MZN ${_produto!.precoPromocional!.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.red,
        ),
      ),
    ] else
      Text(
        'MZN ${_produto!.preco.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.teal,
        ),
      ),
  ],
),
                  const SizedBox(height: 16),
                  
                  // Estoque
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: estoqueEsgotado ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: estoqueEsgotado ? Colors.red : Colors.green,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          estoqueEsgotado ? Icons.block : Icons.inventory_2,
                          color: estoqueEsgotado ? Colors.red : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          estoqueEsgotado
                              ? 'Estoque Esgotado'
                              : 'Estoque Disponível: $estoque unidades',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: estoqueEsgotado ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Se NÃO estiver esgotado, mostra controles
                  if (!estoqueEsgotado) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    
                    // Quantidade
                    const Text(
                      'Quantidade',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: _decrementarQuantidade,
                          icon: const Icon(Icons.remove_circle),
                          iconSize: 40,
                          color: Colors.red,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.teal, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _quantidade.toString(),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _incrementarQuantidade,
                          icon: const Icon(Icons.add_circle),
                          iconSize: 40,
                          color: Colors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Total
                    Container(
                      padding: const EdgeInsets.all(16),
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
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'MZN ${_calcularTotal().toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Botão Adicionar ao Pedido
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isAdicionando ? null : _adicionarAoPedido,
                        icon: _isAdicionando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(temPedidoAtivo ? Icons.add : Icons.add_shopping_cart),
                        label: Text(
                          _isAdicionando 
                              ? 'Adicionando...' 
                              : temPedidoAtivo 
                                  ? 'Adicionar ao Pedido #$pedidoAtivoId'
                                  : 'Criar Novo Pedido',
                          style: const TextStyle(fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}