// lib/screens/gerenciar_produtos.dart

import 'package:flutter/material.dart';
import '../models/produto.dart';
import '../services/base_de_dados.dart';

import 'package:collection/collection.dart';
import 'dart:io';
import '../widgets/app_sidebar.dart';
import '../widgets/theme_toggle_widget.dart';
import '../services/servico_logs.dart';


class GerenciarProdutosScreen extends StatefulWidget {
  const GerenciarProdutosScreen({super.key});

  @override
  State<GerenciarProdutosScreen> createState() => _GerenciarProdutosScreenState();
}

class _GerenciarProdutosScreenState extends State<GerenciarProdutosScreen> {
  final DatabaseService _dbService = DatabaseService.instance;
  late Future<List<Produto>> _produtosFuture;

  @override
  void initState() {
    super.initState();
    _produtosFuture = _fetchProdutos();
  }

  Future<List<Produto>> _fetchProdutos() async {
    return await _dbService.readAllProdutosWithAssoc();
  }

  void _refreshProducts() {
    setState(() {
      _produtosFuture = _fetchProdutos();
    });
  }

//   Future<void> _confirmDelete(BuildContext context, Produto produto) async {
//     final confirmed = await showDialog<bool>(
//       context: context,
//       builder: (ctx) => AlertDialog(
//         title: const Text('Confirmar Exclusão'),
//         content: Text('Tem certeza que deseja excluir o produto "${produto.nome}" (ID: ${produto.id})? Esta ação é irreversível.'),
//         actions: <Widget>[
//           TextButton(
//             child: const Text('Cancelar'),
//             onPressed: () => Navigator.of(ctx).pop(false),
//           ),
//           TextButton(
//             child: const Text('Excluir', style: TextStyle(color: Colors.red)),
//             onPressed: () => Navigator.of(ctx).pop(true),
//           ),
//         ],
//       ),
//     );

//     if (confirmed == true && produto.id != null) {
//       try {
//         await _dbService.deleteProduto(produto.id!);
//         // 🔥 ADICIONAR LOG
// await ServicoLogs.instance.registrarExclusaoProduto(produto!.nome);

//         _refreshProducts();
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Produto excluído com sucesso!')),
//         );
//       } catch (e) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Erro ao excluir: $e')),
//         );
//       }
//     }
//   }

  // 💡 NOVO: Widget para exibir o status do estoque com código de cores
  Widget _buildEstoqueIndicator(int? quantidade) {
    if (quantidade == null) {
      return const SizedBox.shrink(); // Não exibe nada se não controla estoque
    }

    Color corFundo;
    Color corTexto;
    Color corIcone;
    String texto;
    IconData icone;

    if (quantidade == 0) {
      // 🔴 ESGOTADO
      corFundo = Colors.red.shade50;
      corTexto = Colors.red.shade900;
      corIcone = Colors.red.shade700;
      texto = 'Esgotado';
      icone = Icons.remove_circle_outline;
    } else if (quantidade < 10) {
      // 🟠 ESTOQUE BAIXO
      corFundo = Colors.orange.shade50;
      corTexto = Colors.orange.shade900;
      corIcone = Colors.orange.shade700;
      texto = '$quantidade unidades';
      icone = Icons.warning_amber_rounded;
    } else {
      // 🟢 ESTOQUE NORMAL
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
        backgroundColor:  Colors.deepOrange,
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
            return Center(child: Text('Erro ao carregar produtos: ${snapshot.error}'));
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
              
              final imagemPrincipal = produto.imagens?.firstWhereOrNull((img) => img.isPrincipal);
              final caminhoImagem = imagemPrincipal?.caminho;

              return Card(
                elevation: 4,
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: ListTile(
                  leading: SizedBox(
                    width: 60,
                    height: 60,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: caminhoImagem != null && caminhoImagem.isNotEmpty
                        ? Image.file(
                            File(caminhoImagem),
                            fit: BoxFit.cover, 
                            width: 60,
                            height: 60,
                          ) 
                        : CircleAvatar(
                            backgroundColor: produto.ativo == 1 
                              ? Colors.teal.shade100 
                              : Colors.grey.shade300,
                            child: Text(produto.nome[0]),
                          ),
                    ),
                  ),
                  
                  title: Text(
                    produto.nome,
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      color: produto.ativo == 1 ? Colors.black : Colors.grey
                    ),
                  ),
                  
                    subtitle: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const SizedBox(height: 4),
    Text('Preço: MZN ${produto.preco.toStringAsFixed(2)}'),
    
    // 🔥 EXIBIR PROMO APENAS SE TIVER CATEGORIA CORRETA
    if (produto.precoPromocional != null && 
        produto.categoriasAssociadas?.any((c) => c.nome == 'Promoções da Semana') == true)
      Text(
        'Promoção: MZN ${produto.precoPromocional!.toStringAsFixed(2)}', 
        style: const TextStyle(
          color: Colors.red, 
          fontWeight: FontWeight.bold
        ),
      ),
                      
                      // 💡 NOVO: Indicador Visual de Estoque com Código de Cores
                      _buildEstoqueIndicator(produto.quantidadeEstoque),
                      
                      const SizedBox(height: 6),
                      // Exibir categorias associadas
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
                      // Botão Editar
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () async {
                          await Navigator.of(context).pushNamed(
                            '/editar_produto', 
                            arguments: produto.id,
                          );
                          _refreshProducts();
                        },
                      ),
                      // Botão Excluir
                      // IconButton(
                      //   icon: const Icon(Icons.delete, color: Colors.red),
                      //   onPressed: () => _confirmDelete(context, produto),
                      // ),
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