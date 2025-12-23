// lib/screens/gerenciar_categorias.dart (NOVO ARQUIVO)

import 'package:flutter/material.dart';
import '../models/categoria.dart';
import '../services/base_de_dados.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/theme_toggle_widget.dart';
import '../services/supabase_sync_service.dart';


class GerenciarCategoriasScreen extends StatefulWidget {
  const GerenciarCategoriasScreen({super.key});

  @override
  State<GerenciarCategoriasScreen> createState() => _GerenciarCategoriasScreenState();
}

class _GerenciarCategoriasScreenState extends State<GerenciarCategoriasScreen> {
  late Future<List<Categoria>> _categoriasFuture;
  final DatabaseService _dbService = DatabaseService.instance;
    final SupabaseSyncService _syncService = SupabaseSyncService.instance;

  @override
  void initState() {
    super.initState();
    _categoriasFuture = _loadCategorias();
  }

  // Função para buscar as categorias e seus produtos
  Future<List<Categoria>> _loadCategorias() async {
    return _dbService.readAllCategoriasWithProdutos();
  }
  
  // Função para recarregar a lista após CRUD
  void _recarregarLista() {
    setState(() {
      _categoriasFuture = _loadCategorias();
    });
  }

  // Lógica para Excluir Categoria
  Future<void> _excluirCategoria(int id, String nome) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Tem certeza que deseja excluir a categoria "$nome"? Isso removerá todas as associações com produtos, mas não os produtos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _syncService.deleteCategoria(id);
      _recarregarLista();
      // Opcional: Mostrar Toast/Snackbar de sucesso
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Categoria "$nome" excluída com sucesso!')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Categorias'),
        backgroundColor:  Colors.deepOrange,
        actions: [
          ThemeToggleWidget(showLabel: false),
          // Botão Recarregar (mantido)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _recarregarLista,
          ),
        ],
      ),
       drawer: const AppSidebar(currentRoute: '/gerenciar_categorias'),
      // 💡 POSIÇÃO ESTRATÉGICA: Botão de Cadastro (FAB)
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nova Categoria'),
        onPressed: () async {
          // Navega para a tela de cadastro
          await Navigator.of(context).pushNamed('/cadastrar_categoria'); 
          _recarregarLista(); // Recarrega após o retorno
        },
      ),

      body: FutureBuilder<List<Categoria>>(
        future: _categoriasFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar categorias: ${snapshot.error}'));
          } else if (snapshot.hasData && snapshot.data!.isEmpty) {
            return const Center(child: Text('Nenhuma categoria cadastrada.'));
          } else {
            final categorias = snapshot.data!;
            
            return ListView.builder(
              itemCount: categorias.length,
              itemBuilder: (context, index) {
                final categoria = categorias[index];
                
                // Formata a lista de produtos associados
                final produtos = categoria.produtosAssociados;
                final produtosText = produtos != null && produtos.isNotEmpty
                    ? produtos.map((p) => p.nome).join(', ')
                    : 'Nenhum produto associado.';
                
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    
                    title: Text(
                        categoria.nome,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    
                    subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(categoria.descricao ?? 'Sem descrição.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey.shade600)),
                            const SizedBox(height: 5),
                            const Text('Produtos Associados:', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text(produtosText),
                        ],
                    ),
                    
                    isThreeLine: true,
                    
                    // 💡 BOTÕES DE AÇÃO: Editar e Excluir
                    trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            // Botão Editar
                            IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () async {
                                    await Navigator.of(context).pushNamed(
                                        '/editar_categoria',
                                        arguments: categoria.id, // Passa o ID para edição
                                    );
                                    _recarregarLista();
                                },
                            ),
                            const SizedBox(width: 8),
                            // Botão Excluir
                            IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _excluirCategoria(categoria.id!, categoria.nome),
                            ),
                        ],
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}