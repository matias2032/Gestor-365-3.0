// lib/screens/editar_categoria.dart (NOVO ARQUIVO)

import 'package:flutter/material.dart';
import '../models/categoria.dart';
import '../models/produto.dart';
import '../services/base_de_dados.dart';
import '../services/servico_logs.dart';
import '../services/supabase_sync_service.dart';

// Classe auxiliar para gerenciar os dados da edição
class CategoriaData {
  Categoria? categoria;
  List<Produto> todosProdutos = [];
  List<Produto> produtosSelecionados = [];

  CategoriaData({this.categoria, required this.todosProdutos, required this.produtosSelecionados});
}

class EditarCategoriaScreen extends StatefulWidget {
  final int categoriaId;

  // Recebe o ID da categoria
  const EditarCategoriaScreen({super.key, required this.categoriaId});

  @override
  State<EditarCategoriaScreen> createState() => _EditarCategoriaScreenState();
}

class _EditarCategoriaScreenState extends State<EditarCategoriaScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _descricaoController = TextEditingController();
  final DatabaseService _dbService = DatabaseService.instance;
  final SupabaseSyncService _syncService = SupabaseSyncService.instance;

  late Future<CategoriaData> _categoriaDataFuture;
  Categoria? _categoriaOriginal;
  List<Produto> _produtosSelecionados = [];
  List<Produto> _todosProdutosDisponiveis = [];

  @override
  void initState() {
    super.initState();
    _categoriaDataFuture = _loadCategoriaData(widget.categoriaId);
  }

  // Função para carregar dados (Categoria + Todos os Produtos Ativos)
  Future<CategoriaData> _loadCategoriaData(int id) async {
    final categoria = await _dbService.readCategoriaWithProdutosById(id);
    final todosProdutos = await _dbService.readAllProdutosSimples();

    if (categoria == null) {
      throw Exception('Categoria não encontrada.');
    }

    // Identifica quais produtos da lista geral já estão associados à categoria
    final idsProdutosAssociados = categoria.produtosAssociados?.map((p) => p.id).toSet() ?? {};
    
    // Filtra os objetos Produto da lista geral que correspondem aos associados
    final produtosAtualmenteSelecionados = todosProdutos
        .where((p) => idsProdutosAssociados.contains(p.id))
        .toList();

    return CategoriaData(
      categoria: categoria,
      todosProdutos: todosProdutos,
      produtosSelecionados: produtosAtualmenteSelecionados,
    );
  }

  // Lógica principal de atualização
  Future<void> _salvarEdicao() async {
    if (_formKey.currentState!.validate()) {
      if (_categoriaOriginal == null || _categoriaOriginal!.id == null) return;
      
      final categoriaAtualizada = Categoria(
        id: _categoriaOriginal!.id,
        nome: _nomeController.text.trim(),
        descricao: _descricaoController.text.trim().isEmpty ? null : _descricaoController.text.trim(),
      );
      
      // Obtém os IDs dos produtos selecionados
      final idsProdutos = _produtosSelecionados.map((p) => p.id!).toList();

      try {
        await _syncService.updateCategoria(categoriaAtualizada, idsProdutos);
        await _syncService.forcarSincronizacaoCompleta(); // 🔥 NOVO
        
        // 🔥 ADICIONAR LOG
await ServicoLogs.instance.registrarEdicaoCategoria(_nomeController.text.trim());
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Categoria "${categoriaAtualizada.nome}" atualizada com sucesso!')),
        );
        Navigator.of(context).pop(); // Retorna para a tela de lista
        
      } catch (e) {
        // Tratar erro do DB
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar categoria: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Categoria'),
        backgroundColor:  Colors.deepOrange,
      ),
      body: FutureBuilder<CategoriaData>(
        future: _categoriaDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } 
          
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar dados: ${snapshot.error}'));
          }
          
          final data = snapshot.data!;
          
          // 💡 Inicializa controladores e estados APENAS após o Future estar completo
          if (_nomeController.text.isEmpty) {
            _categoriaOriginal = data.categoria;
            _nomeController.text = data.categoria!.nome;
            _descricaoController.text = data.categoria!.descricao ?? '';
            _todosProdutosDisponiveis = data.todosProdutos;
            _produtosSelecionados = data.produtosSelecionados;
          }
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // --- ID da Categoria ---
                  Text('ID: ${data.categoria!.id}', style: TextStyle(color: Colors.grey.shade700, fontSize: 16)),
                  const SizedBox(height: 20),

                  // --- Campo Nome da Categoria ---
                  TextFormField(
                    controller: _nomeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome da Categoria',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'O nome da categoria é obrigatório.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // --- Campo Descrição (Opcional) ---
                  TextFormField(
                    controller: _descricaoController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descrição (Opcional)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  const Text(
                    'Associar Produtos Ativos', 
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                  ),
                  const Divider(),
                  
                  // --- Seleção de Produtos para Associação ---
                  if (_todosProdutosDisponiveis.isEmpty)
                    const Text('Nenhum produto ativo encontrado para associação.'),
                  
                  if (_todosProdutosDisponiveis.isNotEmpty)
                    Column(
                      children: _todosProdutosDisponiveis.map((produto) {
                        // Verifica se o produto está na lista de selecionados (comparando por ID)
                        final isSelected = _produtosSelecionados.any((p) => p.id == produto.id);
                        
                        return CheckboxListTile(
                          title: Text(produto.nome),
                          subtitle: Text('ID: ${produto.id}'),
                          value: isSelected,
                          onChanged: (bool? newValue) {
                            setState(() {
                              if (newValue == true) {
                                // Adiciona o objeto Produto completo
                                _produtosSelecionados.add(produto);
                              } else {
                                // Remove o produto por ID
                                _produtosSelecionados.removeWhere((p) => p.id == produto.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  
                  const SizedBox(height: 40),

                  // --- Botão Salvar ---
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _salvarEdicao,
                      icon: const Icon(Icons.save),
                      label: const Text('Salvar Alterações', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}