// lib/screens/cadastrar_categoria.dart (NOVO ARQUIVO)

import 'package:flutter/material.dart';
import '../models/categoria.dart';
import '../models/produto.dart';
import '../services/base_de_dados.dart';
import '../services/servico_logs.dart';
import '../services/supabase_sync_service.dart';


class CadastrarCategoriaScreen extends StatefulWidget {
  const CadastrarCategoriaScreen({super.key});

  @override
  State<CadastrarCategoriaScreen> createState() => _CadastrarCategoriaScreenState();
}

class _CadastrarCategoriaScreenState extends State<CadastrarCategoriaScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _descricaoController = TextEditingController();
  final DatabaseService _dbService = DatabaseService.instance;
  final SupabaseSyncService _syncService = SupabaseSyncService.instance;

  // Estado para os produtos disponíveis e selecionados
  late Future<List<Produto>> _produtosDisponiveisFuture;
  final List<Produto> _produtosSelecionados = [];

  @override
  void initState() {
    super.initState();
    // Carrega a lista de produtos disponíveis para associação
    _produtosDisponiveisFuture = _dbService.readAllProdutosSimples(); 
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    super.dispose();
  }

  // Lógica principal de cadastro
  Future<void> _salvarCategoria() async {
    if (_formKey.currentState!.validate()) {
      final novaCategoria = Categoria(
        nome: _nomeController.text.trim(),
        descricao: _descricaoController.text.trim().isEmpty ? null : _descricaoController.text.trim(),
      );
      
      // Obtém os IDs dos produtos selecionados
      final idsProdutos = _produtosSelecionados.map((p) => p.id!).toList();
try {
  await _syncService.createCategoria(novaCategoria, idsProdutos);
  
 
  
  await ServicoLogs.instance.registrarCadastroCategoria(_nomeController.text.trim());
  
  // 🔥 VERIFICAR mounted ANTES de usar context
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Categoria "${novaCategoria.nome}" cadastrada e sincronizada!')),
    );
    Navigator.of(context).pop();
  }
} catch (e) {
        // Tratar erro do DB
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao cadastrar categoria: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastrar Nova Categoria'),
        backgroundColor: Colors.deepOrange,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
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
              FutureBuilder<List<Produto>>(
                future: _produtosDisponiveisFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Erro ao carregar produtos: ${snapshot.error}'));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Text('Nenhum produto ativo encontrado para associação.');
                  } else {
                    final produtosDisponiveis = snapshot.data!;
                    
                    return Column(
                      children: produtosDisponiveis.map((produto) {
                        final isSelected = _produtosSelecionados.contains(produto);
                        
                        return CheckboxListTile(
                          title: Text(produto.nome),
                          subtitle: Text('ID: ${produto.id}'),
                          value: isSelected,
                          onChanged: (bool? newValue) {
                            setState(() {
                              if (newValue == true) {
                                // Adiciona o produto à lista de selecionados
                                _produtosSelecionados.add(produto);
                              } else {
                                // Remove o produto da lista de selecionados
                                _produtosSelecionados.removeWhere((p) => p.id == produto.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    );
                  }
                },
              ),
              
              const SizedBox(height: 40),

              // --- Botão Salvar ---
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _salvarCategoria,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar Categoria', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}