// lib/screens/dashboard.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../widgets/app_sidebar.dart';
import '../services/base_de_dados.dart';
import '../widgets/estoque_alerta_popup.dart';
import '../widgets/conectividade_indicator.dart';
import '../services/sessao_service.dart';
import '../services/sync_events_service.dart'; // 🔥 NOVO
import 'dart:async'; // 🔥 SE JÁ NÃO EXISTIR


class DashboardVendasScreen extends StatefulWidget {
  const DashboardVendasScreen({super.key});

  @override
  State<DashboardVendasScreen> createState() => _DashboardVendasScreenState();
}

enum PeriodoFiltro { hoje, semana, mes, tresMeses, seisMeses, ano }

class _DashboardVendasScreenState extends State<DashboardVendasScreen> {
   StreamSubscription<SyncEvent>? _syncEventsSubscription;

  PeriodoFiltro _filtroAtual = PeriodoFiltro.semana;
  bool _isLoading = true;
  int? _perfilUsuario;
List<Map<String, dynamic>> _desempenhoFuncionarios = [];

  // Dados dos gráficos
  List<Map<String, dynamic>> _dadosPizza = [];
  List<Map<String, dynamic>> _dadosBarra = [];
  
  // Dados de análise de produtos
  List<Map<String, dynamic>> _top5Produtos = [];
  List<Map<String, dynamic>> _produtosNaoVendidos = [];

  @override
void initState() {
  super.initState();
  _perfilUsuario = SessaoService.instance.usuarioAtual?.idPerfil;
  _carregarDados();
  Timer? _reloadTimer;

_syncEventsSubscription = SyncEventsService.instance.eventStream.listen((event) {
  if (!mounted) return;
  
  // 🔥 DEBOUNCE: Aguardar 2 segundos antes de recarregar
  _reloadTimer?.cancel();
  _reloadTimer = Timer(const Duration(seconds: 2), () {
    if (mounted) {
      _carregarDados();
    }
  });
});

@override
void dispose() {
  _reloadTimer?.cancel(); // 🔥 NÃO ESQUECER
  _syncEventsSubscription?.cancel();
  super.dispose();
}
}

Future<void> _carregarDados() async {
    setState(() => _isLoading = true);

    final dataInicio = _calcularDataInicio();
    final dataIso = dataInicio.toIso8601String();

    try {
   
      final dbService = DatabaseService.instance;
      final db = await dbService.database;

      // 1. Gráfico de Pizza (Vendas por Categoria)
      final pizza = await db.rawQuery('''
        SELECT c.nome_categoria, SUM(ip.subtotal) as total_vendas
        FROM item_pedido ip
        JOIN pedido ped ON ip.id_pedido = ped.id_pedido
        JOIN produto p ON ip.id_produto = p.id_produto
        JOIN produto_categoria pc ON p.id_produto = pc.id_produto
        JOIN categoria c ON pc.id_categoria = c.id_categoria
        WHERE ped.data_pedido >= ? AND ped.status_pedido = 'finalizado'
        GROUP BY c.nome_categoria
        ORDER BY total_vendas DESC
      ''', [dataIso]);

      // 2. Gráfico de Barras (Evolução de Vendas)
      final barra = await db.rawQuery('''
        SELECT substr(data_pedido, 1, 10) as data, SUM(total) as total_vendas
        FROM pedido
        WHERE data_pedido >= ? AND status_pedido = 'finalizado'
        GROUP BY substr(data_pedido, 1, 10)
        ORDER BY data ASC
      ''', [dataIso]);

      // 3. Top 5 Produtos Mais Vendidos
      final top5 = await db.rawQuery('''
        SELECT 
          p.nome_produto,
          SUM(ip.quantidade) as quantidade_vendida,
          SUM(ip.subtotal) as receita_total,
          COUNT(DISTINCT ip.id_pedido) as num_pedidos
        FROM item_pedido ip
        JOIN pedido ped ON ip.id_pedido = ped.id_pedido
        JOIN produto p ON ip.id_produto = p.id_produto
        WHERE ped.data_pedido >= ? AND ped.status_pedido = 'finalizado'
        GROUP BY p.id_produto, p.nome_produto
        ORDER BY quantidade_vendida DESC
        LIMIT 5
      ''', [dataIso]);

      // 4. Produtos Não Vendidos no Período
      final naoVendidos = await db.rawQuery('''
        SELECT 
          p.id_produto,
          p.nome_produto,
          p.preco,
          p.quantidade_estoque
        FROM produto p
        WHERE p.ativo = 1
        AND p.id_produto NOT IN (
          SELECT DISTINCT ip.id_produto
          FROM item_pedido ip
          JOIN pedido ped ON ip.id_pedido = ped.id_pedido
          WHERE ped.data_pedido >= ? AND ped.status_pedido = 'finalizado'
        )
        ORDER BY p.nome_produto ASC
      ''', [dataIso]);


// 5. Desempenho de Funcionários (apenas Admin) - 🔥 INCLUI CARGO
List<Map<String, dynamic>> desempenho = [];
if (_perfilUsuario == 1) {
  desempenho = await db.rawQuery('''
    SELECT 
      u.id_usuario,
      u.nome || ' ' || u.apelido as nome_completo,
      CASE u.idperfil
        WHEN 1 THEN 'Administrador'
        WHEN 2 THEN 'Gerente'
        WHEN 3 THEN 'Funcionário'
        ELSE 'Usuário'
      END as cargo,
      COUNT(DISTINCT ped.id_pedido) as total_pedidos,
      SUM(ped.total) as total_vendas,
      COUNT(DISTINCT DATE(ped.data_pedido)) as dias_ativos
    FROM pedido ped
    INNER JOIN usuario u ON ped.id_usuario = u.id_usuario
    WHERE ped.data_pedido >= ? 
      AND ped.status_pedido = 'finalizado'
      AND u.idperfil IN (1, 2, 3)
    GROUP BY u.id_usuario, u.nome, u.apelido, u.idperfil
    ORDER BY total_vendas DESC
  ''', [dataIso]);

}

      setState(() {
        _dadosPizza = pizza;
        _dadosBarra = barra;
        _top5Produtos = top5;
        _produtosNaoVendidos = naoVendidos;
        _isLoading = false;
        _desempenhoFuncionarios = desempenho;
      });
    } catch (e) {
      debugPrint('Erro ao carregar dashboard: $e');
      setState(() => _isLoading = false);
    }
  }

  DateTime _calcularDataInicio() {
    final hoje = DateTime.now();
    switch (_filtroAtual) {
      case PeriodoFiltro.hoje:
        return DateTime(hoje.year, hoje.month, hoje.day);
      case PeriodoFiltro.semana:
        return hoje.subtract(const Duration(days: 7));
      case PeriodoFiltro.mes:
        return DateTime(hoje.year, hoje.month - 1, hoje.day);
      case PeriodoFiltro.tresMeses:
        return DateTime(hoje.year, hoje.month - 3, hoje.day);
      case PeriodoFiltro.seisMeses:
        return DateTime(hoje.year, hoje.month - 6, hoje.day);
      case PeriodoFiltro.ano:
        return DateTime(hoje.year - 1, hoje.month, hoje.day);
    }
  }

Widget build(BuildContext context) {
  return Stack(
    children: [
      Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard de Vendas'),
          backgroundColor: Colors.deepOrange,
          actions: [
             const ConectividadeIndicator(), 
            IconButton(
              icon: const Icon(Icons.analytics_outlined),
              onPressed: () => _mostrarAnaliseDetalhada(context),
              tooltip: 'Análise Detalhada',
            ),
          ],
        ),
        drawer: const AppSidebar(currentRoute: '/dashboard'),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _carregarDados,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFiltroDropdown(),
                      const SizedBox(height: 20),
                      _buildResumoCards(),
                      const SizedBox(height: 20),
                      _buildGraficoBarras(),
                      const SizedBox(height: 30),
                      _buildGraficoPizza(),
                      const SizedBox(height: 30),
                      _buildTop5Section(),
                      if (_perfilUsuario == 1) // Apenas administradores
  const SizedBox(height: 30),
if (_perfilUsuario == 1)
  _buildDesempenhoFuncionarios(),
                    ],
                  ),
                ),
              ),
      ),
      const EstoqueAlertaPopup(), // ✅ JÁ EXISTE
    ],
  );
}

  

  Widget _buildFiltroDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PeriodoFiltro>(
          value: _filtroAtual,
          isExpanded: true,
          onChanged: (value) {
            if (value != null) {
              setState(() => _filtroAtual = value);
              _carregarDados();
            }
          },
          items: const [
            DropdownMenuItem(value: PeriodoFiltro.hoje, child: Text('Hoje')),
            DropdownMenuItem(value: PeriodoFiltro.semana, child: Text('Últimos 7 dias')),
            DropdownMenuItem(value: PeriodoFiltro.mes, child: Text('Último Mês')),
            DropdownMenuItem(value: PeriodoFiltro.tresMeses, child: Text('Últimos 3 Meses')),
            DropdownMenuItem(value: PeriodoFiltro.seisMeses, child: Text('Últimos 6 Meses')),
            DropdownMenuItem(value: PeriodoFiltro.ano, child: Text('Último Ano')),
          ],
        ),
      ),
    );
  }

Widget _buildResumoCards() {
  final totalVendas = _dadosBarra.fold<double>(
    0,
    (sum, item) => sum + ((item['total_vendas'] as num?)?.toDouble() ?? 0),
  );
  
  // 🔥 REMOVIDO: cálculo de ticket médio e segundo card
  return _buildCard(
    'Total de Vendas',
    'MT ${totalVendas.toStringAsFixed(2)}',
    Icons.attach_money,
    Colors.green,
  );
}

  Widget _buildCard(String titulo, String valor, IconData icone, Color cor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.shade200, blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 32),
          const SizedBox(height: 8),
          Text(titulo, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 4),
          Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildGraficoBarras() {
    if (_dadosBarra.isEmpty) {
      return _buildEmptyState('Sem dados de vendas para este período.');
    }

    final maxY = _dadosBarra
        .map((e) => (e['total_vendas'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b) * 1.2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Evolução de Vendas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(
          height: 300,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 6)],
          ),
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx >= 0 && idx < _dadosBarra.length) {
                        final date = DateTime.parse(_dadosBarra[idx]['data'] as String);
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(DateFormat('dd/MM').format(date), style: const TextStyle(fontSize: 10)),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text('${value.toInt()}', style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              barGroups: _dadosBarra.asMap().entries.map((entry) {
                final valor = (entry.value['total_vendas'] as num).toDouble();
                return BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(
                      toY: valor,
                      color: Colors.blue,
                      width: 16,
                      borderRadius: BorderRadius.circular(4),
                      // Data Label fixo no topo da barra
                      rodStackItems: [],
                    ),
                  ],
                  showingTooltipIndicators: [0],
                );
              }).toList(),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final valor = rod.toY;
                    return BarTooltipItem(
                      'MT ${valor.toStringAsFixed(2)}',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGraficoPizza() {
    if (_dadosPizza.isEmpty) {
      return _buildEmptyState('Sem dados de categoria para este período.');
    }

    final colors = [Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple, Colors.amber];
    final total = _dadosPizza.fold<double>(0, (sum, item) => sum + ((item['total_vendas'] as num?)?.toDouble() ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Vendas por Categoria', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(
          height: 300,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 6)],
          ),
          child: Row(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: _dadosPizza.asMap().entries.map((entry) {
                      final valor = (entry.value['total_vendas'] as num).toDouble();
                      final percentual = (valor / total * 100).toStringAsFixed(1);
                      return PieChartSectionData(
                        color: colors[entry.key % colors.length],
                        value: valor,
                        title: '$percentual%',
                        radius: 50,
                        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _dadosPizza.asMap().entries.map((entry) {
                  final nome = entry.value['nome_categoria'] as String;
                  final valor = (entry.value['total_vendas'] as num).toDouble();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(width: 12, height: 12, color: colors[entry.key % colors.length]),
                        const SizedBox(width: 8),
                        Text('$nome\nMT ${valor.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTop5Section() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Top 5 Produtos Mais Vendidos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: () => _mostrarAnaliseDetalhada(context),
              icon: const Icon(Icons.analytics),
              label: const Text('Ver Detalhes'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._top5Produtos.map((produto) => _buildProdutoCard(produto)),
      ],
    );
  }

  Widget _buildProdutoCard(Map<String, dynamic> produto) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 4)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(produto['nome_produto'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Quantidade: ${produto['quantidade_vendida']} | Receita: MT ${(produto['receita_total'] as num).toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${produto['num_pedidos']} pedidos', style: TextStyle(color: Colors.green.shade700, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String mensagem) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(mensagem, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  void _mostrarAnaliseDetalhada(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepOrange,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Análise Completa de Produtos', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSecaoAnalise('Top 5 Mais Vendidos', _top5Produtos, Colors.green),
                  const SizedBox(height: 20),
                  _buildSecaoAnalise('Produtos Sem Vendas (${_produtosNaoVendidos.length})', _produtosNaoVendidos, Colors.orange),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecaoAnalise(String titulo, List<Map<String, dynamic>> produtos, Color cor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cor)),
        const SizedBox(height: 8),
        if (produtos.isEmpty)
          const Text('Nenhum produto nesta categoria.')
        else
          ...produtos.map((p) {
            if (p.containsKey('quantidade_vendida')) {
              return ListTile(
                title: Text(p['nome_produto'] as String),
                subtitle: Text('Vendidos: ${p['quantidade_vendida']} | Receita: MT ${(p['receita_total'] as num).toStringAsFixed(2)}'),
                trailing: Chip(label: Text('${p['num_pedidos']} pedidos'), backgroundColor: Colors.green.shade50),
              );
            } else {
              return ListTile(
                title: Text(p['nome_produto'] as String),
                subtitle: Text('Estoque: ${p['quantidade_estoque']} | Preço: MT ${(p['preco'] as num).toStringAsFixed(2)}'),
                trailing: const Icon(Icons.warning_amber, color: Colors.orange),
              );
            }
          }),
      ],
    );
  }

  // ADICIONAR este método na classe _DashboardVendasScreenState:
Widget _buildDesempenhoFuncionarios() {
  if (_desempenhoFuncionarios.isEmpty) {
    return _buildEmptyState('Sem dados de desempenho para este período.');
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.leaderboard, color: Colors.deepOrange),
          const SizedBox(width: 8),
          const Text(
            'Desempenho de usuários',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      const SizedBox(height: 10),
      
      // Ranking em cards
      ..._desempenhoFuncionarios.asMap().entries.map((entry) {
        final index = entry.key;
        final func = entry.value;
        
        final medalha = index == 0 ? '🥇' : index == 1 ? '🥈' : index == 2 ? '🥉' : '${index + 1}º';
        final corBorda = index == 0 ? Colors.amber : index == 1 ? Colors.grey : index == 2 ? Colors.orange.shade700 : Colors.blue.shade100;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: corBorda, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    medalha,
                    style: const TextStyle(fontSize: 28),
                  ),
                  const SizedBox(width: 12),
                Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 🔥 NOVO: Exibir cargo antes do nome
      Text(
        func['cargo'] as String,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        func['nome_completo'] as String,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(
        '${func['total_pedidos']} pedidos em ${func['dias_ativos']} dias',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[600],
        ),
      ),
    ],
  ),
),
                 // Dentro do Row dos dados do funcionário, substituir a Column à direita:
Column(
  crossAxisAlignment: CrossAxisAlignment.end,
  children: [
    Text(
      'MT ${(func['total_vendas'] as num).toStringAsFixed(2)}',
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.green,
      ),
    ),
    // 🔥 REMOVIDO: texto do ticket médio
  ],
),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Barra de progresso visual
              Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: (func['total_vendas'] as num) / 
                        (_desempenhoFuncionarios.first['total_vendas'] as num),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade400, Colors.teal],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    ],
  );
}
}