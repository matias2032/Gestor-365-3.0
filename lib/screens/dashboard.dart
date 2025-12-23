// lib/screens/dashboard.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/base_de_dados.dart';
import '../widgets/app_sidebar.dart';



class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum PeriodoFiltro { hoje, semana, mes, tresMeses, seisMeses, ano }

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _dbService = DatabaseService.instance;
  PeriodoFiltro _filtroAtual = PeriodoFiltro.semana;
  bool _isLoading = true;

  // Dados para os gráficos
  List<Map<String, dynamic>> _dadosPizza = [];
  List<Map<String, dynamic>> _dadosBarra = [];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  // Calcula a data inicial baseada no filtro e carrega dados
  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);

    DateTime dataInicio;
    final hoje = DateTime.now();

    switch (_filtroAtual) {
      case PeriodoFiltro.hoje:
        dataInicio = DateTime(hoje.year, hoje.month, hoje.day);
        break;
      case PeriodoFiltro.semana:
        dataInicio = hoje.subtract(const Duration(days: 7));
        break;
      case PeriodoFiltro.mes:
        dataInicio = DateTime(hoje.year, hoje.month - 1, hoje.day);
        break;
      case PeriodoFiltro.tresMeses:
        dataInicio = DateTime(hoje.year, hoje.month - 3, hoje.day);
        break;
      case PeriodoFiltro.seisMeses:
        dataInicio = DateTime(hoje.year, hoje.month - 6, hoje.day);
        break;
      case PeriodoFiltro.ano:
        dataInicio = DateTime(hoje.year - 1, hoje.month, hoje.day);
        break;
    }

    final dataIso = dataInicio.toIso8601String();

    try {
      final pizza = await _dbService.getVendasPorCategoria(dataIso);
      final barra = await _dbService.getVendasCronologicas(dataIso);

      setState(() {
        _dadosPizza = pizza;
        _dadosBarra = barra;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar dashboard: $e');
      setState(() => _isLoading = false);
    }
  }

  // --- Widgets da UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: Colors.deepOrange,
      ),
      // Menu Lateral (Drawer)

      drawer: const AppSidebar(currentRoute: '/dashboard'),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filtro de Período
                  _buildFiltroDropdown(),
                  const SizedBox(height: 20),

                  // Gráfico 1: Barras (Vendas no Tempo)
                  const Text("Evolução de Vendas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  _buildBarChartContainer(),

                  const SizedBox(height: 30),

                  // Gráfico 2: Pizza (Vendas por Categoria)
                  const Text("Vendas por Categoria", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  _buildPieChartContainer(),
                ],
              ),
            ),
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
          onChanged: (PeriodoFiltro? newValue) {
            if (newValue != null) {
              setState(() {
                _filtroAtual = newValue;
              });
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

  Widget _buildBarChartContainer() {
    if (_dadosBarra.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text("Sem dados para este período.")));
    }

    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 6)]),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _dadosBarra.map((e) => (e['total_vendas'] as num).toDouble()).reduce((a, b) => a > b ? a : b) * 1.2,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < _dadosBarra.length) {
                    final dateStr = _dadosBarra[index]['data'] as String;
                    final date = DateTime.parse(dateStr);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(DateFormat('dd/MM').format(date), style: const TextStyle(fontSize: 10)),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: _dadosBarra.asMap().entries.map((entry) {
            final valor = (entry.value['total_vendas'] as num).toDouble();
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(toY: valor, color: Colors.blue, width: 16, borderRadius: BorderRadius.circular(4)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPieChartContainer() {
    if (_dadosPizza.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text("Sem dados para este período.")));
    }

    // Cores fixas para categorias
    final colors = [Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple, Colors.amber];

    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 6)]),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: _dadosPizza.asMap().entries.map((entry) {
                  final valor = (entry.value['total_vendas'] as num).toDouble();
                  final color = colors[entry.key % colors.length];
                  return PieChartSectionData(
                    color: color,
                    value: valor,
                    title: '${valor.toStringAsFixed(0)}',
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Legenda
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _dadosPizza.asMap().entries.map((entry) {
              final nome = entry.value['nome_categoria'] as String;
              final color = colors[entry.key % colors.length];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(width: 12, height: 12, color: color),
                    const SizedBox(width: 8),
                    Text(nome, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}