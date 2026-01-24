
// lib/screens/menu.dart (COM CONTADOR SINCRONIZADO)

import 'package:flutter/material.dart';
import 'dart:async';
import '../models/produto.dart';
import '../models/categoria.dart';
import '../services/base_de_dados.dart';
import '../services/pedido_ativo_service.dart';
import '../services/pedido_contador_service.dart'; // 🔥 NOVO IMPORT
import '../models/produto_imagem.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/theme_toggle_widget.dart';
import '../services/supabase_sync_service.dart';
import '../services/sessao_service.dart';
import '../widgets/estoque_alerta_popup.dart';
import '../widgets/cached_produto_image.dart';
import '../widgets/conectividade_indicator.dart';
import '../services/conectividade_service.dart';



class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService.instance;
  final PedidoAtivoService _pedidoAtivoService = PedidoAtivoService.instance;
  final PedidoContadorService _contadorService = PedidoContadorService.instance; // 🔥 NOVO
  final _syncService = SupabaseSyncService.instance;
  
  late Future<List<Produto>> _produtosFuture;
  late AnimationController _animationController;
  
  StreamSubscription<void>? _estoqueSubscription;
  StreamSubscription<int>? _contadorSubscription; // 🔥 NOVO
  
  // Filtros
  List<Categoria> _categorias = [];
  int? _categoriaSelecionada;
  String _buscaNome = '';
  double? _precoMin;
  double? _precoMax;
  bool _mostrarFiltros = false;
  
  // Contador de pedidos
  int _contadorPedidos = 0;
  
  // Controladores
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _precoMinController = TextEditingController();
  final TextEditingController _precoMaxController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.forward();

    _sincronizarSeNecessario();

    _produtosFuture = _fetchProdutos();
    _fetchCategorias();
    _atualizarContadorPedidos();
    
    // Escutar mudanças no estoque
    _estoqueSubscription = _dbService.estoqueStream.listen((_) {
      if (mounted) {
        setState(() {
          _produtosFuture = _fetchProdutos();
        });
      }
    });
    
    // 🔥 NOVO: Escutar mudanças no contador global
    _contadorPedidos = _contadorService.contadorAtual;
    _contadorSubscription = _contadorService.contadorStream.listen((novoValor) {
      if (mounted) {
        setState(() {
          _contadorPedidos = novoValor;
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nomeController.dispose();
    _precoMinController.dispose();
    _precoMaxController.dispose();
    _estoqueSubscription?.cancel();
    _contadorSubscription?.cancel(); // 🔥 NOVO
    super.dispose();
  }
  // ADICIONAR MÉTODO NOVO:
Future<void> _sincronizarSeNecessario() async {
  final ultimaSync = _syncService.lastSyncTime;
  final agora = DateTime.now();
  
  // 🔥 CRÍTICO: Só sincronizar se passou 5+ minutos
  if (ultimaSync == null || 
      agora.difference(ultimaSync).inMinutes > 5) {
    print('⏱️ Última sync há ${ultimaSync != null ? agora.difference(ultimaSync).inMinutes : "∞"} min - sincronizando...');
    await _syncService.sincronizarSeletivo(sincronizarMovimentos: false);
    
    // 🔥 NOVO: Marcar que foi feita uma sync
    ConectividadeService.instance.marcarSyncCompleta();
  } else {
    print('✅ Dados recentes (última sync há ${agora.difference(ultimaSync).inMinutes}min) - usando cache local');
  }
}


 Future<void> _atualizarContadorPedidos() async {
  try {
    // 🔥 USAR ID DO USUÁRIO LOGADO
    final usuario = SessaoService.instance.usuarioAtual;
    if (usuario == null) return;
    
    final pedidos = await _syncService.readPedidosPorFinalizar(usuario.id!);
    final novoContador = pedidos.length;
    
    // Atualiza o serviço global
    _contadorService.atualizarContador(novoContador);
    
    if (mounted) {
      setState(() {
        _contadorPedidos = novoContador;
      });
    }
  } catch (e) {
    print('Erro ao contar pedidos: $e');
  }
}


Future<List<Produto>> _fetchProdutos() async {
  try {
    // 🔥 LEITURA PURA DO BANCO LOCAL (SEM SYNC)
    final produtos = await _dbService.readAllProdutosWithAssoc();
    
    return produtos.where((p) {
      if (p.ativo != 1) return false;
      
      if (_buscaNome.isNotEmpty && 
          !p.nome.toLowerCase().contains(_buscaNome.toLowerCase())) {
        return false;
      }
      
      if (_precoMin != null && p.preco < _precoMin!) return false;
      if (_precoMax != null && p.preco > _precoMax!) return false;
      
      if (_categoriaSelecionada != null) {
        final temCategoria = p.categoriasAssociadas?.any(
          (c) => c.id == _categoriaSelecionada
        ) ?? false;
        if (!temCategoria) return false;
      }
      
      return true;
    }).toList();
  } catch (e) {
    print('Erro ao buscar produtos: $e');
    return [];
  }
}
  Future<void> _fetchCategorias() async {
    try {
      final categorias = await _dbService.readAllCategoriasSimples();
      if (mounted) {
        setState(() {
          _categorias = categorias;
        });
      }
    } catch (e) {
      print('Erro ao buscar categorias: $e');
    }
  }

  void _aplicarFiltros() {
    setState(() {
      _buscaNome = _nomeController.text.trim();
      _precoMin = double.tryParse(_precoMinController.text);
      _precoMax = double.tryParse(_precoMaxController.text);
      _produtosFuture = _fetchProdutos();
    });
  }

  void _limparFiltros() {
    setState(() {
      _nomeController.clear();
      _precoMinController.clear();
      _precoMaxController.clear();
      _categoriaSelecionada = null;
      _buscaNome = '';
      _precoMin = null;
      _precoMax = null;
      _produtosFuture = _fetchProdutos();
    });
  }

  Future<void> _iniciarNovoPedido() async {
    if (!_pedidoAtivoService.temPedidoAtivo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há pedido ativo no momento.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_shopping_cart, color: Colors.teal),
            SizedBox(width: 12),
            Text('Novo Pedido'),
          ],
        ),
        content: Text(
          'Deseja iniciar um novo pedido?\n\n'
          'O Pedido #${_pedidoAtivoService.pedidoAtivoId} será desmarcado como ativo '
          'e o próximo produto será adicionado a um novo pedido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check),
            label: const Text('Sim, Novo Pedido'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmado == true) {
      _pedidoAtivoService.limparPedidoAtivo();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pedido ativo limpo. O próximo produto criará um novo pedido.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        setState(() {});
      }
    }
  }

  Color _getEstoqueColor(int? estoque) {
    if (estoque == null || estoque == 0) return Colors.red;
    if (estoque < 10) return Colors.orange;
    return Colors.green;
  }

  String _getEstoqueText(int? estoque) {
    if (estoque == null || estoque == 0) return 'Esgotado';
    if (estoque < 10) return 'Estoque Baixo ($estoque)';
    return '$estoque unidades';
  }

 Widget _buildProdutoCard(Produto produto, int index) {
  final imagemPrincipal = produto.imagens?.firstWhere(
    (img) => img.isPrincipal,
    orElse: () => ProdutoImagem(
      idProduto: produto.id!,
      caminho: '',
      isPrincipal: false,
    ),
  );

  final caminhoImagem = imagemPrincipal?.caminho ?? '';
  final estoque = produto.quantidadeEstoque ?? 0;
  final temPromocao = produto.precoPromocional != null && 
      produto.categoriasAssociadas?.any((c) => c.nome == 'Promoções da Semana') == true;

  return FadeTransition(
    opacity: CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ),
    child: Card(
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.of(context).pushNamed(
            '/detalhes_produto',
            arguments: produto.id,
          );
          setState(() {
            _produtosFuture = _fetchProdutos();
          });
          _atualizarContadorPedidos();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedProdutoImage( // 🔥 WIDGET NOVO
                      imagePath: caminhoImagem,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: Container(
                        color: Colors.grey.shade200,
                        child: Icon(
                          Icons.image_not_supported,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                  if (temPromocao)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'PROMO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ), Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                   Wrap(
  spacing: 6,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
    Text(
      'MZN ${produto.preco.toStringAsFixed(2)}',
      style: TextStyle(
        fontSize: 14,
        color: Colors.teal,
        fontWeight: FontWeight.w700,
        decoration: temPromocao ? TextDecoration.lineThrough : TextDecoration.none,
      ),
    ),
    if (temPromocao)
      Text(
        'MZN ${produto.precoPromocional!.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 15,
          color: Colors.red,
          fontWeight: FontWeight.bold,
        ),
      ),
  ],
),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getEstoqueColor(estoque).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2,
                            size: 14,
                            color: _getEstoqueColor(estoque),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _getEstoqueText(estoque),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _getEstoqueColor(estoque),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
Widget build(BuildContext context) {
  final temPedidoAtivo = _pedidoAtivoService.temPedidoAtivo;
  final pedidoAtivoId = _pedidoAtivoService.pedidoAtivoId;

  // 1. O retorno agora começa com um Stack
  return Stack(
    children: [
      // 2. O seu Scaffold original é o primeiro filho do Stack (fica no fundo)
      Scaffold(
        appBar: AppBar(
          title: const Text('Menu'),
          backgroundColor: Colors.deepOrange,
          elevation: 4,
          actions: [
             const ConectividadeIndicator(), 
            ThemeToggleWidget(showLabel: false),
            IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _mostrarFiltros ? Icons.filter_alt_off : Icons.filter_alt,
                  key: ValueKey(_mostrarFiltros),
                ),
              ),
              tooltip: 'Filtros',
              onPressed: () {
                setState(() {
                  _mostrarFiltros = !_mostrarFiltros;
                });
              },
            ),
            if (temPedidoAtivo)
              IconButton(
                icon: const Icon(Icons.add_shopping_cart),
                tooltip: 'Novo Pedido',
                onPressed: _iniciarNovoPedido,
              ),
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.receipt_long),
                  tooltip: 'Pedidos Por Finalizar',
                  onPressed: () async {
                    await Navigator.of(context)
                        .pushNamed('/pedidos_por_finalizar');
                    _atualizarContadorPedidos();
                    setState(() {});
                  },
                ),
                if (_contadorPedidos > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Center(
                        child: Text(
                          '$_contadorPedidos',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        drawer: const AppSidebar(currentRoute: '/menu'),
        body: Column(
          children: [
            if (temPedidoAtivo)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.teal.shade200, width: 2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.teal,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shopping_bag,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pedido Ativo',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          Text(
                            'Pedido #$pedidoAtivoId - Produtos serão adicionados aqui',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.teal),
                      tooltip: 'Novo Pedido',
                      onPressed: _iniciarNovoPedido,
                    ),
                  ],
                ),
              ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _mostrarFiltros
                  ? Container(
                      color: Colors.grey.shade100,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Filtros',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nomeController,
                            decoration: const InputDecoration(
                              labelText: 'Nome do Produto',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _precoMinController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Preço Mínimo',
                                    prefixText: 'MZN ',
                                    border: OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _precoMaxController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Preço Máximo',
                                    prefixText: 'MZN ',
                                    border: OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: _categoriaSelecionada,
                            decoration: const InputDecoration(
                              labelText: 'Categoria',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
                                child: Text('Todas as Categorias'),
                              ),
                              ..._categorias.map((cat) => DropdownMenuItem<int>(
                                    value: cat.id,
                                    child: Text(cat.nome),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _categoriaSelecionada = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _aplicarFiltros,
                                  icon: const Icon(Icons.check),
                                  label: const Text('Aplicar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _limparFiltros,
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Limpar'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: FutureBuilder<List<Produto>>(
                future: _produtosFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 60, color: Colors.red.shade300),
                          const SizedBox(height: 16),
                          Text(
                            'Erro ao carregar produtos',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    );
                  }

                  final produtos = snapshot.data ?? [];

                  if (produtos.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 100,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Nenhum produto encontrado',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 230,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent: 275,
                    ),
                    itemCount: produtos.length,
                    itemBuilder: (context, index) =>
                        _buildProdutoCard(produtos[index], index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      
      // 3. ADICIONADO AQUI: O Popup sobrepõe o Scaffold
      const EstoqueAlertaPopup(), 
    ],
  );
}
}