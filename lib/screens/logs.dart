// lib/screens/logs.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/base_de_dados.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/conectividade_indicator.dart';


enum TipoFiltroLog {
  todos,
  login,
  logout,
  cadastro,
  edicao,
  exclusao,
}

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  late Future<List<Map<String, dynamic>>> _logsFuture;
  TipoFiltroLog _filtroAtual = TipoFiltroLog.todos;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _logsFuture = _loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadLogs() async {
    final db = DatabaseService.instance;
    final result = await db.database;

    String whereClause = '';
    List<dynamic> whereArgs = [];

    // Aplicar filtro por tipo de ação
    if (_filtroAtual != TipoFiltroLog.todos) {
      final tipoAcao = _getTipoAcaoFromFiltro(_filtroAtual);
      whereClause = 'WHERE l.acao LIKE ?';
      whereArgs.add('%$tipoAcao%');
    }

    // Aplicar filtro de busca
    if (_searchQuery.isNotEmpty) {
      if (whereClause.isEmpty) {
        whereClause = 'WHERE';
      } else {
        whereClause += ' AND';
      }
      whereClause += ' (u.nome LIKE ? OR u.apelido LIKE ? OR l.acao LIKE ?)';
      whereArgs.addAll(['%$_searchQuery%', '%$_searchQuery%', '%$_searchQuery%']);
    }

    final logsMaps = await result.rawQuery('''
      SELECT 
        l.id_log,
        l.id_usuario,
        l.acao,
        l.data_hora,
        u.nome || ' ' || u.apelido as nome_usuario,
        u.email as email_usuario
      FROM logs l
      LEFT JOIN usuario u ON l.id_usuario = u.id_usuario
      $whereClause
      ORDER BY l.data_hora DESC
      LIMIT 1000
    ''', whereArgs);

    return logsMaps;
  }

  String _getTipoAcaoFromFiltro(TipoFiltroLog filtro) {
    switch (filtro) {
      case TipoFiltroLog.login:
        return 'Login';
      case TipoFiltroLog.logout:
        return 'Logout';
      case TipoFiltroLog.cadastro:
        return 'Cadastro';
      case TipoFiltroLog.edicao:
        return 'Edição';
      case TipoFiltroLog.exclusao:
        return 'Exclusão';
      default:
        return '';
    }
  }

  String _getFiltroLabel(TipoFiltroLog filtro) {
    switch (filtro) {
      case TipoFiltroLog.todos:
        return 'Todos';
      case TipoFiltroLog.login:
        return 'Login';
      case TipoFiltroLog.logout:
        return 'Logout';
      case TipoFiltroLog.cadastro:
        return 'Cadastros';
      case TipoFiltroLog.edicao:
        return 'Edições';
      case TipoFiltroLog.exclusao:
        return 'Exclusões';
    }
  }

  IconData _getFiltroIcon(TipoFiltroLog filtro) {
    switch (filtro) {
      case TipoFiltroLog.todos:
        return Icons.list_alt;
      case TipoFiltroLog.login:
        return Icons.login;
      case TipoFiltroLog.logout:
        return Icons.logout;
      case TipoFiltroLog.cadastro:
        return Icons.add_circle;
      case TipoFiltroLog.edicao:
        return Icons.edit;
      case TipoFiltroLog.exclusao:
        return Icons.delete;
    }
  }

  Color _getAcaoColor(String acao) {
    if (acao.toLowerCase().contains('login')) {
      return Colors.green;
    } else if (acao.toLowerCase().contains('logout')) {
      return Colors.orange;
    } else if (acao.toLowerCase().contains('cadastro') || 
               acao.toLowerCase().contains('criou') ||
               acao.toLowerCase().contains('adicionou')) {
      return Colors.blue;
    } else if (acao.toLowerCase().contains('edição') || 
               acao.toLowerCase().contains('alterou') ||
               acao.toLowerCase().contains('atualizou')) {
      return Colors.purple;
    } else if (acao.toLowerCase().contains('exclusão') || 
               acao.toLowerCase().contains('deletou') ||
               acao.toLowerCase().contains('removeu')) {
      return Colors.red;
    }
    return Colors.grey;
  }

  IconData _getAcaoIcon(String acao) {
    if (acao.toLowerCase().contains('login')) {
      return Icons.login;
    } else if (acao.toLowerCase().contains('logout')) {
      return Icons.logout;
    } else if (acao.toLowerCase().contains('cadastro') || 
               acao.toLowerCase().contains('criou') ||
               acao.toLowerCase().contains('adicionou')) {
      return Icons.add_circle_outline;
    } else if (acao.toLowerCase().contains('edição') || 
               acao.toLowerCase().contains('alterou') ||
               acao.toLowerCase().contains('atualizou')) {
      return Icons.edit_outlined;
    } else if (acao.toLowerCase().contains('exclusão') || 
               acao.toLowerCase().contains('deletou') ||
               acao.toLowerCase().contains('removeu')) {
      return Icons.delete_outline;
    }
    return Icons.info_outline;
  }

  void _aplicarFiltro() {
    setState(() {
      _logsFuture = _loadLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Logs do Sistema (${_getFiltroLabel(_filtroAtual)})'),
        backgroundColor: Colors.deepOrange,
        actions: [
          const ConectividadeIndicator(),
          ThemeToggleWidget(showLabel: false),
          PopupMenuButton<TipoFiltroLog>(
            icon: Icon(_getFiltroIcon(_filtroAtual)),
            tooltip: 'Filtrar por tipo',
            onSelected: (TipoFiltroLog newFilter) {
              setState(() {
                _filtroAtual = newFilter;
                _logsFuture = _loadLogs();
              });
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<TipoFiltroLog>>[
              const PopupMenuItem(
                value: TipoFiltroLog.todos,
                child: Row(
                  children: [
                    Icon(Icons.list_alt),
                    SizedBox(width: 8),
                    Text('Todos'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: TipoFiltroLog.login,
                child: Row(
                  children: [
                    Icon(Icons.login, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Login'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: TipoFiltroLog.logout,
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: TipoFiltroLog.cadastro,
                child: Row(
                  children: [
                    Icon(Icons.add_circle, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Cadastros'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: TipoFiltroLog.edicao,
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Colors.purple),
                    SizedBox(width: 8),
                    Text('Edições'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: TipoFiltroLog.exclusao,
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Exclusões'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: () {
              setState(() {
                _logsFuture = _loadLogs();
              });
            },
          ),
        ],
      ),
      drawer: const AppSidebar(currentRoute: '/logs'),
      body: Column(
        children: [
          // Barra de busca
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.deepOrange.shade50,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por usuário ou ação...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _logsFuture = _loadLogs();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              onSubmitted: (value) {
                _aplicarFiltro();
              },
            ),
          ),

          // Lista de logs
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _logsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 60,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Erro ao carregar logs: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final logs = snapshot.data ?? [];

                if (logs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'Nenhum log encontrado com "$_searchQuery"'
                              : 'Nenhum log ${_getFiltroLabel(_filtroAtual).toLowerCase()} encontrado',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: logs.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return _buildLogCard(log);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final acao = log['acao'] as String? ?? 'Ação desconhecida';
    final dataHora = log['data_hora'] as String?;
    final nomeUsuario = log['nome_usuario'] as String? ?? 'Sistema';
    final emailUsuario = log['email_usuario'] as String?;

    final dataFormatada = dataHora != null
        ? DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.parse(dataHora))
        : 'Data desconhecida';

    final acaoColor = _getAcaoColor(acao);
    final acaoIcon = _getAcaoIcon(acao);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: acaoColor.withOpacity(0.2),
          child: Icon(
            acaoIcon,
            color: acaoColor,
          ),
        ),
        title: Text(
          acao,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    nomeUsuario,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (emailUsuario != null)
              Row(
                children: [
                  const Icon(Icons.email, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      emailUsuario,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  dataFormatada,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: acaoColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: acaoColor.withOpacity(0.3)),
          ),
          child: Text(
            '#${log['id_log']}',
            style: TextStyle(
              color: acaoColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}