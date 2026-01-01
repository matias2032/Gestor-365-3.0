// lib/screens/editar_produto.dart

import 'package:flutter/material.dart';
import '../services/base_de_dados.dart';
import '../models/produto.dart';
import '../models/categoria.dart';
import '../models/produto_imagem.dart';
import '../services/servico_logs.dart';
import '../services/servico_movimento_estoque.dart';
import '../services/sessao_service.dart';

// Importações dos pacotes externos
import 'package:collection/collection.dart'; 
import 'package:file_picker/file_picker.dart';
import '../services/persistencia_ficheiro.dart';
import '../services/supabase_sync_service.dart';

class EditarProdutoScreen extends StatefulWidget {
  final int produtoId;

  const EditarProdutoScreen({super.key, required this.produtoId});

  @override
  State<EditarProdutoScreen> createState() => _EditarProdutoScreenState();
}

class _EditarProdutoScreenState extends State<EditarProdutoScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService.instance;
  final ServicoMovimentoEstoque _movimentoService = ServicoMovimentoEstoque.instance;

  // Controladores do Produto
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _precoController = TextEditingController();
  final TextEditingController _precoPromoController = TextEditingController();
  final TextEditingController _estoqueController = TextEditingController();
  final TextEditingController _motivoEstoqueController = TextEditingController(); // 🔥 NOVO
    final SupabaseSyncService _syncService = SupabaseSyncService.instance;

  Produto? _produtoOriginal; 
  List<ProdutoImagem> _imagensAtuais = [];
  List<TextEditingController> _imagemControllers = []; 
  
  bool _ativo = true;
  // bool _isDestaque = false;
  bool _isLoading = true;

  // Categorias
  List<Categoria> _todasCategorias = [];
  Set<int> _categoriasSelecionadas = {}; 
  
  bool _showPrecoPromocionalField = false;
  static const String _nomeCategoriaPromocao = 'Promoções da Semana';

  // Variáveis para rastrear mudança de estoque
  int? _estoqueOriginal;
  bool _estoqueAlterado = false;

  @override
  void initState() {
    super.initState();
    _loadProdutoData();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _precoPromoController.dispose();
    _estoqueController.dispose();
    _motivoEstoqueController.dispose(); // 🔥 NOVO

    for (var controller in _imagemControllers) {
      controller.dispose();
    }
    super.dispose();
  }

void _checkPromotionalStatus() {
  final categoriaPromocao = _todasCategorias.firstWhereOrNull(
    (c) => c.nome == _nomeCategoriaPromocao,
  );

  bool mustShow = false;
  if (categoriaPromocao != null && categoriaPromocao.id != null) {
    mustShow = _categoriasSelecionadas.contains(categoriaPromocao.id!);
  }
  
  if (_showPrecoPromocionalField != mustShow) {
    setState(() {
      _showPrecoPromocionalField = mustShow;
      // 🔥 RESET: Limpar campo ao desassociar categoria
      if (!_showPrecoPromocionalField) {
        _precoPromoController.clear();
      }
    });
  }
}

  Future<void> _loadProdutoData() async {
    try {
      final produto = await _dbService.readProdutoWithDetailsById(widget.produtoId);
      final todasCategorias = await _dbService.readAllCategoriasSimples();

      if (produto != null) {
        _produtoOriginal = produto;
        
        _nomeController.text = produto.nome;
        _descricaoController.text = produto.descricao ?? '';
        _precoController.text = produto.preco.toString();
        _precoPromoController.text = produto.precoPromocional?.toString() ?? '';
        _estoqueController.text = produto.quantidadeEstoque?.toString() ?? '';
        
        _estoqueOriginal = produto.quantidadeEstoque;
        
        _ativo = produto.ativo == 1;
        // _isDestaque = produto.isDestaque == 1;
        
        _todasCategorias = todasCategorias;
        _categoriasSelecionadas = produto.categoriasAssociadas?.map((c) => c.id!).toSet() ?? {};

        _imagensAtuais = produto.imagens ?? [];
        
        _imagemControllers = _imagensAtuais.map((img) => TextEditingController(text: img.caminho)).toList();
        _imagemControllers.add(TextEditingController()); 
        
        _checkPromotionalStatus(); 
        
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Produto não encontrado!')),
          );
          Navigator.of(context).pop();
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar dados: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<String?> _pickFileReal() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image, 
        allowMultiple: false, 
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Imagem selecionada: ${path.split('/').last}')),
            );
          }
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

  // 🔥 ATUALIZADO: Agora usa o motivo do campo de texto
  Future<void> _registrarMovimentoSeNecessario(int novoEstoque) async {
    if (_estoqueOriginal == null || _estoqueOriginal == novoEstoque) {
      return;
    }

    final idUsuario = SessaoService.instance.usuarioAtual?.id;
    if (idUsuario == null) {
      throw Exception('Usuário não identificado');
    }

    // 🔥 NOVO: Usa o motivo do campo ou valor padrão
    final motivo = _motivoEstoqueController.text.trim().isEmpty 
        ? 'Edição manual do produto'
        : _motivoEstoqueController.text.trim();

    await _movimentoService.registrarMovimentoManual(
      idProduto: _produtoOriginal!.id!,
      idUsuario: idUsuario,
      quantidadeAnterior: _estoqueOriginal!,
      quantidadeNova: novoEstoque,
      motivo: motivo,
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || _produtoOriginal == null || _produtoOriginal!.id == null) {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Erro: Não foi possível carregar o produto original ou ID inválido.')),
            );
        }
        return;
    }

    setState(() => _isLoading = true);
    final produtoId = _produtoOriginal!.id!;

    try {
        final novoEstoque = int.tryParse(_estoqueController.text.trim());
        
      final produtoAtualizado = _produtoOriginal!.copyWith(
  nome: _nomeController.text.trim(),
  descricao: _descricaoController.text.trim().isEmpty ? null : _descricaoController.text.trim(),
  preco: double.tryParse(_precoController.text.replaceAll(',', '.')) ?? 0.0,
  // 🔥 RESET GARANTIDO: Se não mostrar campo = NULL no BD
  precoPromocional: _showPrecoPromocionalField && _precoPromoController.text.isNotEmpty
      ? double.tryParse(_precoPromoController.text.replaceAll(',', '.'))
      : null, // 🔥 IMPORTANTE: Define como NULL para resetar no BD
  ativo: _ativo ? 1 : 0,
  // isDestaque: _isDestaque ? 1 : 0,
  quantidadeEstoque: novoEstoque,
);
        final idsCategorias = _categoriasSelecionadas.toList();
        final List<ProdutoImagem> imagensParaSalvar = [];

        for (var i = 0; i < _imagemControllers.length; i++) {
            final caminhoDoControlador = _imagemControllers[i].text.trim();
            
            if (caminhoDoControlador.isNotEmpty) {
                ProdutoImagem? imagemOriginal = _imagensAtuais.firstWhereOrNull((img) => img.caminho == caminhoDoControlador);
                String caminhoFinal;
                int? imagemId = imagemOriginal?.id;

                if (imagemOriginal != null) {
                    caminhoFinal = caminhoDoControlador;
                } else {
                    final caminhoPermanente = await saveImagePermanently(caminhoDoControlador);
                    if (caminhoPermanente == null) {
                         throw Exception("Não foi possível salvar a nova imagem ${i + 1} (Falha na persistência). Operação abortada.");
                    }
                    caminhoFinal = caminhoPermanente;
                    imagemId = null;
                }

                imagensParaSalvar.add(
                    ProdutoImagem(
                        id: imagemId,
                        idProduto: produtoId,
                        caminho: caminhoFinal,
                        isPrincipal: i == 0,
                    )
                );
            }
        }

        // Registrar movimento ANTES de atualizar o produto
        if (novoEstoque != null) {
          await _registrarMovimentoSeNecessario(novoEstoque);
        }

        await _syncService.updateProduto(produtoAtualizado, idsCategorias, imagensParaSalvar);
        await _syncService.forcarSincronizacaoCompleta(); // 🔥 NOVO
        // 🔥 ADICIONAR LOG
        await ServicoLogs.instance.registrarEdicaoProduto(_nomeController.text.trim());

        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Produto atualizado com sucesso!')),
            );
            Navigator.of(context).pop(true);
        }
    } catch (e) {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Falha ao atualizar produto: $e')),
            );
        }
    } finally {
        setState(() => _isLoading = false);
    }
  }

  Widget _buildImageField(TextEditingController controller, int index) {
    final caminho = controller.text;
    final isPrincipal = (index == 0) && caminho.isNotEmpty; 

    return Padding(
       padding: const EdgeInsets.only(bottom: 12.0),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              readOnly: true, 
              decoration: InputDecoration(
                labelText: isPrincipal ? 'Caminho Imagem Principal' : 'Caminho Imagem Adicional ${index + 1}',
                hintText: 'Clique para selecionar o arquivo...',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {}); 
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.blue),
            onPressed: () async {
              final path = await _pickFileReal();
              if (path != null) {
                setState(() {
                  controller.text = path;
                  if (index == _imagemControllers.length - 1) {
                    _imagemControllers.add(TextEditingController());
                  }
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
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Carregando Produto...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Produto: ${_produtoOriginal!.nome}'),
        backgroundColor: Colors.deepOrange,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dados Principais', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
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

              // Campo de estoque com indicador visual
              TextFormField(
                controller: _estoqueController,
                decoration: InputDecoration(
                  labelText: 'Quantidade em Estoque',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.inventory_2),
                  helperText: _estoqueOriginal != null 
                      ? 'Estoque atual: $_estoqueOriginal unidades'
                      : 'Deixe em branco se não controlar estoque',
                  suffixIcon: _estoqueController.text.isNotEmpty && 
                              int.tryParse(_estoqueController.text) != _estoqueOriginal
                      ? const Tooltip(
                          message: 'Alteração de estoque será registrada',
                          child: Icon(Icons.warning_amber, color: Colors.orange),
                        )
                      : null,
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  setState(() {
                    final novoEstoque = int.tryParse(value);
                    _estoqueAlterado = novoEstoque != null && novoEstoque != _estoqueOriginal;
                  });
                },
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
              
              // 🔥 NOVO: Campo de Motivo (aparece quando há alteração)
              if (_estoqueAlterado) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _motivoEstoqueController,
                  decoration: const InputDecoration(
                    labelText: 'Motivo da Alteração (Opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes),
                    hintText: 'Ex: Correção de inventário, perda, dano...',
                    helperText: 'Descreva o motivo da alteração no estoque',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Esta alteração será registrada no histórico de movimentos de estoque',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: SwitchListTile(
                      title: const Text('Ativo'),
                      value: _ativo,
                      onChanged: (val) => setState(() => _ativo = val),
                      tileColor: Colors.deepOrange.shade50,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Expanded(
                  //   child: SwitchListTile(
                  //     title: const Text('Destaque'),
                  //     value: _isDestaque,
                  //     onChanged: (val) => setState(() => _isDestaque = val),
                  //     tileColor: Colors.deepOrange.shade50,
                  //   ),
                  // ),
                ],
              ),
              const SizedBox(height: 24),
              
              const Text('Categorias Associadas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
              const Divider(),

              if (_todasCategorias.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16.0),
                  child: Text('Nenhuma categoria encontrada.'),
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
                          _checkPromotionalStatus();
                        });
                      },
                      selectedColor: Colors.deepOrange.shade200,
                      checkmarkColor: Colors.white,
                    );
                  }).toList(),
                ),
              
              const SizedBox(height: 24),

              const Text('Imagens do Produto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
              const Divider(),
              const Text('A primeira imagem preenchida será a principal. Use o X para remover um slot.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),

              ..._imagemControllers.asMap().entries.map((entry) {
                return _buildImageField(entry.value, entry.key);
              }).toList(),
              
              if (_imagemControllers.last.text.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar mais imagem'),
                    onPressed: () {
                      setState(() {
                        _imagemControllers.add(TextEditingController());
                      });
                    },
                  ),
                ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _submitForm,
                  icon: const Icon(Icons.save),
                  label: Text(_isLoading ? 'Atualizando...' : 'Salvar Alterações', style: const TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
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