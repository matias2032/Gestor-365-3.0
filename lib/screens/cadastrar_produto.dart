// lib/screens/cadastrar_produto.dart

import 'package:flutter/material.dart';
// Serviços e Modelos Locais
import '../services/base_de_dados.dart';
import '../models/produto.dart';
import '../models/categoria.dart';
import '../models/produto_imagem.dart';
import '../services/servico_logs.dart';
import '../services/supabase_sync_service.dart';

// Importações dos pacotes externos
import 'package:collection/collection.dart'; 
import 'package:file_picker/file_picker.dart';
import '../services/persistencia_ficheiro.dart'; // Importação do serviço de persistência de ficheiros

class CadastrarProdutoScreen extends StatefulWidget {
  const CadastrarProdutoScreen({super.key});

  @override
  State<CadastrarProdutoScreen> createState() => _CadastrarProdutoScreenState();
}

class _CadastrarProdutoScreenState extends State<CadastrarProdutoScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService.instance;
  final SupabaseSyncService _syncService = SupabaseSyncService.instance;

  // Controladores do Produto
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _precoController = TextEditingController();
  final TextEditingController _precoPromoController = TextEditingController();
  final TextEditingController _estoqueController = TextEditingController();

  // Controladores de Imagem (Simulando 3 slots de upload inicialmente)
  final List<TextEditingController> _imagemControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  // Estado
  bool _ativo = true;
  // bool _isDestaque = false;
  bool _isLoading = false;

  // Categorias
  List<Categoria> _todasCategorias = [];
  Set<int> _categoriasSelecionadas = {}; 
  
  // Variável de estado para controlar a visibilidade do campo promocional
  bool _showPrecoPromocionalField = false;
  // Nome da categoria que dispara a promoção (DEVE corresponder ao nome real na sua BD)
  static const String _nomeCategoriaPromocao = 'Promoções da Semana';


  @override
  void initState() {
    super.initState();
    _fetchCategorias();
  }
  
  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _precoPromoController.dispose();
    _estoqueController.dispose();
    for (var controller in _imagemControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchCategorias() async {
    setState(() => _isLoading = true);
    try {
      _todasCategorias = await _dbService.readAllCategoriasSimples();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar categorias: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  // Função para verificar se a categoria de promoção está selecionada
  void _checkPromotionalStatus() {
  final categoriaPromocao = _todasCategorias.firstWhereOrNull(
    (c) => c.nome == _nomeCategoriaPromocao,
  );

  bool mustShow = false;
  if (categoriaPromocao != null && categoriaPromocao.id != null) {
    mustShow = _categoriasSelecionadas.contains(categoriaPromocao.id!);
  }
  
  // 🔥 ATUALIZAÇÃO OTIMIZADA: só setState se houver mudança real
  if (_showPrecoPromocionalField != mustShow) {
    setState(() {
      _showPrecoPromocionalField = mustShow;
      // 🔥 LIMPAR O CAMPO ao ocultar (garantindo reset)
      if (!_showPrecoPromocionalField) {
        _precoPromoController.clear();
      }
    });
  }
}
  
  Future<String?> _pickFileReal() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image, // Filtrar apenas arquivos de imagem
        allowMultiple: false, // Permitir apenas uma seleção por vez
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Imagem selecionada: ${path.split('/').last}')),
            );
          }
          // O caminho temporário/original (path) será retornado para o controlador
          return path;
        }
      }
      return null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir o seletor de arquivos: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Inicializa o processo de salvamento
    setState(() => _isLoading = true);

    try {
      // 1. CONSTRUIR O OBJETO PRODUTO
final novoProduto = Produto(
  nome: _nomeController.text.trim(),
  descricao: _descricaoController.text.trim().isEmpty ? null : _descricaoController.text.trim(),
  preco: double.tryParse(_precoController.text.replaceAll(',', '.')) ?? 0.0,
  // 🔥 GARANTIR QUE SEJA NULL SE NÃO MOSTRAR O CAMPO
  precoPromocional: _showPrecoPromocionalField && _precoPromoController.text.isNotEmpty
      ? double.tryParse(_precoPromoController.text.replaceAll(',', '.'))
      : null,
  ativo: _ativo ? 1 : 0,
  // isDestaque: _isDestaque ? 1 : 0,
  dataCadastro: DateTime.now().toIso8601String(),
  quantidadeEstoque: int.tryParse(_estoqueController.text.trim()),
);

      final idsCategorias = _categoriasSelecionadas.toList();

      // 2. PROCESSAR E PERSISTIR IMAGENS
final List<ProdutoImagem> imagensParaSalvar = [];

for (var i = 0; i < _imagemControllers.length; i++) {
    final caminhoTemporario = _imagemControllers[i].text.trim();
    
    if (caminhoTemporario.isNotEmpty) {
        
        // **Verificação e Persistência da Imagem**
        final caminhoPermanente = await saveImagePermanently(caminhoTemporario);
        
        if (caminhoPermanente != null) {
            // Salvar o NOVO caminho permanente na lista para a base de dados
            imagensParaSalvar.add(ProdutoImagem(
                idProduto: 0, // Será preenchido pelo DB service
                caminho: caminhoPermanente, 
                // CORRIGIDO: Atribui BOOL, não INT
                isPrincipal: i == 0, 
            ));
        } else {
            // AQUI É ONDE O ERRO ESTÁ A OCORRER (saveImagePermanently devolveu null)
            
            // Tratamento de erro específico para a imagem:
            String mensagemErro = 'Falha ao processar a imagem ${i + 1} ($caminhoTemporario). Por favor, tente novamente.';

            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(mensagemErro)),
                );
            }
            
            // Se falhar a imagem principal, lançar a exceção.
            if (i == 0) {
                 throw Exception("Não foi possível salvar a imagem principal. Operação abortada.");
            }
            // Para as imagens secundárias, podemos decidir continuar ou parar.
            // Aqui optamos por parar se falhar a principal (i==0), e apenas reportar se for secundária.
            // Para garantir a integridade do cadastro, é melhor parar aqui também:
            throw Exception("Falha na persistência da imagem ${i + 1}. Cadastro abortado.");
        }
    }
}

      // 3. ENVIAR PARA A BASE DE DADOS
      await _syncService.createProduto(novoProduto, idsCategorias, imagensParaSalvar);
      // 🔥 ADICIONAR LOG
await ServicoLogs.instance.registrarCadastroProduto(_nomeController.text.trim());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produto cadastrado com sucesso!')),
        );
        Navigator.of(context).pop(); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao cadastrar produto: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  // Widget que contém o campo de texto de caminho do ficheiro e o botão de seleção
  Widget _buildImageField(TextEditingController controller, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              readOnly: true, // Impedir edição manual
              decoration: InputDecoration(
                labelText: index == 0 ? 'Caminho Imagem Principal' : 'Caminho Imagem Adicional ${index + 1}',
                hintText: 'Clique no ícone de pasta para selecionar...',
                prefixIcon: const Icon(Icons.image),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (index == 0 && (value == null || value.isEmpty)) {
                  return 'Pelo menos a Imagem Principal é obrigatória.';
                }
                return null;
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.blue),
            onPressed: () async {
              // CHAMA O MÉTODO DE SELEÇÃO
              final path = await _pickFileReal();
              if (path != null) {
                setState(() {
                  // Salva o caminho temporário no controlador. 
                  // Ele será processado (movido) durante o _submitForm.
                  controller.text = path;
                });
              }
            },
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastrar Novo Produto'),
        backgroundColor: Colors.deepOrange,
      ),
      body: _isLoading && _todasCategorias.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- 1. DADOS BÁSICOS ---
                    const Text('Dados do Produto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                    const Divider(),
                    
                    TextFormField(
                      controller: _nomeController,
                      decoration: const InputDecoration(labelText: 'Nome do Produto', border: OutlineInputBorder()),
                      validator: (value) => (value == null || value.isEmpty) ? 'O nome é obrigatório.' : null,
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _descricaoController,
                      decoration: const InputDecoration(labelText: 'Descrição (Opcional)', border: OutlineInputBorder()),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _precoController,
                            decoration: const InputDecoration(labelText: 'Preço', border: OutlineInputBorder(), prefixText: 'MZN '),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              final preco = double.tryParse(value?.replaceAll(',', '.') ?? '');
                              if (preco == null || preco <= 0) return 'Preço válido é obrigatório.';
                              return null;
                            },
                          ),
                        ),
                        // Preço Promocional CONDICIONAL
                        if (_showPrecoPromocionalField) 
                          ...[
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _precoPromoController,
                                decoration: const InputDecoration(labelText: 'Preço Promocional', border: OutlineInputBorder(), prefixText: 'MZN '),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                    if (_showPrecoPromocionalField && (value == null || value.isEmpty)) {
                                        return 'Preço promocional é obrigatório.';
                                    }
                                    final precoPromo = double.tryParse(value?.replaceAll(',', '.') ?? '');
                                    if (_showPrecoPromocionalField && (precoPromo == null || precoPromo <= 0)) {
                                         return 'Insira um preço promocional válido.';
                                    }
                                    return null;
                                },
                              ),
                            ),
                          ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 16),
TextFormField(
  controller: _estoqueController,
  decoration: const InputDecoration(
    labelText: 'Quantidade em Estoque',
    border: OutlineInputBorder(),
    prefixIcon: Icon(Icons.inventory_2),
    helperText: 'Deixe em branco se não controlar estoque',
  ),
  keyboardType: TextInputType.number,
  validator: (value) {
    if (value != null && value.isNotEmpty) {
      final estoque = int.tryParse(value);
      if (estoque == null || estoque < 0) {
        return 'Insira uma quantidade válida (número inteiro positivo)';
      }
    }
    return null;
  },
),
const SizedBox(height: 16),

                    // --- 2. SWITCHES (ATIVO / DESTAQUE) ---
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            title: const Text('Ativo'),
                            value: _ativo,
                            onChanged: (val) => setState(() => _ativo = val),
                            tileColor: Colors.teal.shade50,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Expanded(
                        //   child: SwitchListTile(
                        //     title: const Text('Destaque'),
                        //     value: _isDestaque,
                        //     onChanged: (val) => setState(() => _isDestaque = val),
                        //     tileColor: Colors.teal.shade50,
                        //   ),
                        // ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // --- 3. SELEÇÃO DE CATEGORIAS ---
                    const Text('Categorias Associadas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                    const Divider(),

                    if (_todasCategorias.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16.0),
                        child: Text('Nenhuma categoria encontrada. Cadastre categorias primeiro.'),
                      )
                    else
                      Wrap(
                        spacing: 8.0,
                        children: _todasCategorias.map((categoria) {
                          final isSelected = _categoriasSelecionadas.contains(categoria.id);
                          return FilterChip(
                            label: Text(categoria.nome),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _categoriasSelecionadas.add(categoria.id!);
                                } else {
                                  _categoriasSelecionadas.remove(categoria.id!);
                                }
                                _checkPromotionalStatus(); // CHAMA A LÓGICA CONDICIONAL
                              });
                            },
                            selectedColor: Colors.teal.shade200,
                            checkmarkColor: Colors.white,
                          );
                        }).toList(),
                      ),
                    
                    const SizedBox(height: 24),

                    // --- 4. UPLOAD DE IMAGENS ---
                    const Text('Imagens do Produto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                    const Divider(),
                    const Text('A primeira imagem selecionada será considerada a principal.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),

                    ..._imagemControllers.asMap().entries.map((entry) {
                      return _buildImageField(entry.value, entry.key);
                    }).toList(),

                    const SizedBox(height: 30),

                    // --- 5. BOTÃO DE SUBMISSÃO ---
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _submitForm,
                        icon: const Icon(Icons.save),
                        label: Text(_isLoading ? 'Salvando...' : 'Cadastrar Produto', style: const TextStyle(fontSize: 18)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}