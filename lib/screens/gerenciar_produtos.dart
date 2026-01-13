// lib/screens/gerenciar_produtos.dart

import 'package:flutter/material.dart';
import '../models/produto.dart';
import '../services/supabase_sync_service.dart'; // 🔥 MUDOU
import 'package:collection/collection.dart';
import 'dart:io';
import '../widgets/app_sidebar.dart';
import '../widgets/theme_toggle_widget.dart';
import '../services/estoque_alerta_service.dart';
import '../services/base_de_dados.dart';
import '../widgets/cached_produto_image.dart';


class GerenciarProdutosScreen extends StatefulWidget {
  const GerenciarProdutosScreen({super.key});

  @override
  State<GerenciarProdutosScreen> createState() => _GerenciarProdutosScreenState();
}

class _GerenciarProdutosScreenState extends State<GerenciarProdutosScreen> {
  final SupabaseSyncService _syncService = SupabaseSyncService.instance; // 🔥 MUDOU
  late Future<List<Produto>> _produtosFuture;

  @override
  void initState() {
    super.initState();
    _produtosFuture = _fetchProdutos();
    EstoqueAlertaService.instance.verificarEstoque();
  }

  Future<List<Produto>> _fetchProdutos() async {
    final produtos = await _syncService.readAllProdutosWithAssoc(); // 🔥 MUDOU
    
    produtos.sort((a, b) {
      final qtdA = a.quantidadeEstoque ?? 999;
      final qtdB = b.quantidadeEstoque ?? 999;
      
      if (qtdA < 10 && qtdB >= 10) return -1;
      if (qtdB < 10 && qtdA >= 10) return 1;
      if (qtdA < 20 && qtdB >= 20) return -1;
      if (qtdB < 20 && qtdA >= 20) return 1;
      
      return qtdA.compareTo(qtdB);
    });
    
    return produtos;
  }

  void _refreshProducts() {
    setState(() {
      _produtosFuture = _fetchProdutos();
    });
  }

  Color _getCorBordaEstoque(int? qtd) {
    if (qtd == null || qtd >= 20) return Colors.transparent;
    if (qtd < 10) return Colors.red;
    return Colors.orange;
  }

  // 🔥 CORRIGIDO: Agora usa o método correto
  Future<void> _toggleAtivo(int idProduto, bool novoValor) async {
    try {
      await _syncService.toggleAtivoProduto(idProduto, novoValor);
      await _syncService.forcarSincronizacaoCompleta();
      _refreshProducts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(novoValor ? 'Produto ativado' : 'Produto desativado'),
            backgroundColor: novoValor ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildEstoqueIndicator(int? quantidade) {
    if (quantidade == null) {
      return const SizedBox.shrink();
    }

    Color corFundo;
    Color corTexto;
    Color corIcone;
    String texto;
    IconData icone;

    if (quantidade == 0) {
      corFundo = Colors.red.shade50;
      corTexto = Colors.red.shade900;
      corIcone = Colors.red.shade700;
      texto = 'Esgotado';
      icone = Icons.remove_circle_outline;
    } else if (quantidade < 10) {
      corFundo = Colors.orange.shade50;
      corTexto = Colors.orange.shade900;
      corIcone = Colors.orange.shade700;
      texto = '$quantidade unidades';
      icone = Icons.warning_amber_rounded;
    } else {
      corFundo = Colors.green.shade50;
      corTexto = Colors.green.shade900;
      corIcone = Colors.green.shade700;
      texto = '$quantidade unidades';
      icone = Icons.check_circle_outline;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: corFundo,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: corIcone.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 16, color: corIcone),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                texto,
                style: TextStyle(
                  color: corTexto,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Produtos'),
        backgroundColor: Colors.deepOrange,
        actions: [
          ThemeToggleWidget(showLabel: false),
          IconButton(
            icon: const Icon(Icons.add_box),
            tooltip: 'Cadastrar Novo Produto',
            onPressed: () async {
              await Navigator.of(context).pushNamed('/cadastrar_produto');
              _refreshProducts();
            },
          ),
        ],
      ),
      drawer: const AppSidebar(currentRoute: '/gerenciar_produtos'),
      body: FutureBuilder<List<Produto>>(
        future: _produtosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Text('Erro ao carregar produtos: ${snapshot.error}')
            );
          }

          final produtos = snapshot.data ?? [];

          if (produtos.isEmpty) {
            return const Center(
              child: Text(
                'Nenhum produto cadastrado.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: produtos.length,
            itemBuilder: (context, index) {
              final produto = produtos[index];
              final categorias = produto.categoriasAssociadas ?? [];
              final isAtivo = produto.ativo == 1;
              
              final imagemPrincipal = produto.imagens?.firstWhereOrNull(
                (img) => img.isPrincipal
              );
              final caminhoImagem = imagemPrincipal?.caminho;

              return Card(
                elevation: 4,
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _getCorBordaEstoque(produto.quantidadeEstoque),
                    width: produto.quantidadeEstoque != null && 
                           produto.quantidadeEstoque! < 20 ? 3 : 0,
                  ),
                ),
                child: ListTile(
                 leading: SizedBox(
  width: 60,
  height: 60,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(8.0),
    child: CachedProdutoImage(
      imagePath: caminhoImagem,
      width: 60,
      height: 60,
      fit: BoxFit.cover,
      placeholder: Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: CircleAvatar(
        backgroundColor: isAtivo 
          ? Colors.teal.shade100 
          : Colors.grey.shade300,
        child: Text(produto.nome[0]),
      ),
    ),
  ),
),
                  
                  title: Text(
                    produto.nome,
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      color: isAtivo ? Colors.black : Colors.grey,
                      decoration: isAtivo ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Preço: MZN ${produto.preco.toStringAsFixed(2)}'),
                      
                      if (produto.precoPromocional != null && 
                          produto.categoriasAssociadas?.any(
                            (c) => c.nome == 'Promoções da Semana'
                          ) == true)
                        Text(
                          'Promoção: MZN ${produto.precoPromocional!.toStringAsFixed(2)}', 
                          style: const TextStyle(
                            color: Colors.red, 
                            fontWeight: FontWeight.bold
                          ),
                        ),
                      
                      _buildEstoqueIndicator(produto.quantidadeEstoque),
                      
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6.0,
                        runSpacing: 0,
                        children: [
                          const Text(
                            'Categorias: ', 
                            style: TextStyle(fontWeight: FontWeight.w500)
                          ),
                          if (categorias.isEmpty)
                            const Text(
                              'Nenhuma', 
                              style: TextStyle(fontStyle: FontStyle.italic)
                            ),
                          ...categorias.map((cat) => Chip(
                            label: Text(
                              cat.nome, 
                              style: const TextStyle(fontSize: 12)
                            ),
                            backgroundColor: Colors.teal.shade50,
                            padding: EdgeInsets.zero,
                          )).toList(),
                        ],
                      ),
                    ],
                  ),
                  
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 🔥 TOGGLE CORRIGIDO
                      Switch(
                        value: isAtivo,
                        activeColor: Colors.green,
                        inactiveThumbColor: Colors.grey,
                        onChanged: (valor) async {
                          await _toggleAtivo(produto.id!, valor);
                        },
                      ),
                      const SizedBox(width: 8),
                      
                      // 🔥 BLOQUEIO DE EDIÇÃO PARA PRODUTOS DESATIVADOS
                      IconButton(
                        icon: Icon(
                          Icons.edit,
                          color: isAtivo ? Colors.blue : Colors.grey,
                        ),
                        tooltip: isAtivo 
                          ? 'Editar produto' 
                          : 'Ative o produto para editar',
                        onPressed: isAtivo
                          ? () async {
                              await Navigator.of(context).pushNamed(
                                '/editar_produto', 
                                arguments: produto.id,
                              );
                              _refreshProducts();
                            }
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Ative o produto antes de editá-lo'
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            },
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