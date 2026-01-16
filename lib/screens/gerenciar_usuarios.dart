// lib/screens/gerenciar_usuarios.dart (VERSÃO COM FILTRO POR PERFIL)

import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../services/base_de_dados.dart';
import '../screens/detalhes_usuario.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/conectividade_indicator.dart';


enum StatusFiltro {
  todos,
  ativo,
  inativo,
}

class UsuarioListScreen extends StatefulWidget {
  const UsuarioListScreen({super.key});

  @override
  State<UsuarioListScreen> createState() => _UsuarioListScreenState();
}

class _UsuarioListScreenState extends State<UsuarioListScreen> {
  late Future<List<Usuario>> _usuariosFuture;
  StatusFiltro _filtroAtual = StatusFiltro.todos;

  @override
  void initState() {
    super.initState();
    _usuariosFuture = _loadUsuarios();
  }

  // 🔥 NOVO: Filtra APENAS Gerentes (idperfil=2) e Funcionários (idperfil=3)
  Future<List<Usuario>> _loadUsuarios() async {
    final todosUsuarios = await DatabaseService.instance.readAllUsuarios();
    
    // Primeiro filtro: Apenas Gerentes e Funcionários
    List<Usuario> usuariosFiltrados = todosUsuarios.where((u) {
      return u.idPerfil == 2 || u.idPerfil == 3;
    }).toList();
    
    // Segundo filtro: Por status (ativo/inativo)
    if (_filtroAtual == StatusFiltro.ativo) {
      usuariosFiltrados = usuariosFiltrados.where((u) => u.ativo == 1).toList();
    } else if (_filtroAtual == StatusFiltro.inativo) {
      usuariosFiltrados = usuariosFiltrados.where((u) => u.ativo == 0).toList();
    }
    
    return usuariosFiltrados;
  }

  String _getPerfilName(int? idPerfil) {
    switch (idPerfil) {
      case 1:
        return 'Administrador';
      case 2:
        return 'Gerente';
      case 3:
        return 'Funcionário';
      default:
        return 'Cliente';
    }
  }
  
  String _getFiltroLabel(StatusFiltro filtro) {
    switch (filtro) {
      case StatusFiltro.ativo:
        return 'Ativos';
      case StatusFiltro.inativo:
        return 'Inativos';
      case StatusFiltro.todos:
        return 'Todos';
    }
  }

  IconData _getFiltroIcon(StatusFiltro filtro) {
    switch (filtro) {
      case StatusFiltro.ativo:
        return Icons.person;
      case StatusFiltro.inativo:
        return Icons.person_off;
      case StatusFiltro.todos:
        return Icons.people_alt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Usuários (${_getFiltroLabel(_filtroAtual)})'),
        backgroundColor: Colors.deepOrange,
        actions: [
           const ConectividadeIndicator(), 
          ThemeToggleWidget(showLabel: false),
          
          PopupMenuButton<StatusFiltro>(
            icon: Icon(_getFiltroIcon(_filtroAtual)),
            onSelected: (StatusFiltro newFilter) {
              setState(() {
                _filtroAtual = newFilter;
                _usuariosFuture = _loadUsuarios();
              });
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<StatusFiltro>>[
              const PopupMenuItem<StatusFiltro>(
                value: StatusFiltro.todos,
                child: Text('Mostrar Todos'),
              ),
              const PopupMenuItem<StatusFiltro>(
                value: StatusFiltro.ativo,
                child: Row(
                  children: [
                    Icon(Icons.person, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Apenas Ativos'),
                  ],
                ),
              ),
              const PopupMenuItem<StatusFiltro>(
                value: StatusFiltro.inativo,
                child: Row(
                  children: [
                    Icon(Icons.person_off, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Apenas Inativos'),
                  ],
                ),
              ),
            ],
          ),

          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _usuariosFuture = _loadUsuarios();
              });
            },
          ),
          
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () async {
              await Navigator.of(context).pushNamed('/cadastro_usuario');
              setState(() {
                _usuariosFuture = _loadUsuarios();
              });
            },
          ),
        ],
      ),

      drawer: const AppSidebar(currentRoute: '/gerenciar_usuarios'),
      body: FutureBuilder<List<Usuario>>(
        future: _usuariosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Text('Erro ao carregar usuários: ${snapshot.error}'),
            );
          } else if (snapshot.hasData && snapshot.data!.isEmpty) {
            final message = _filtroAtual == StatusFiltro.todos 
                ? 'Nenhum gerente ou funcionário encontrado.' 
                : 'Nenhum gerente ou funcionário ${_getFiltroLabel(_filtroAtual).toLowerCase()} encontrado.';
            return Center(
              child: Text(message),
            );
          } else {
            final usuarios = snapshot.data!;

            return ListView.builder(
              itemCount: usuarios.length,
              itemBuilder: (context, index) {
                final usuario = usuarios[index];
                final perfilNome = _getPerfilName(usuario.idPerfil);

                final isAtivo = usuario.ativo == 1;
                final statusText = isAtivo ? 'Ativo' : 'Inativo';
                final statusColor = isAtivo ? Colors.green : Colors.red;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(usuario.nome[0]),
                    ),

                    title: RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          TextSpan(
                            text: '${usuario.nome} ${usuario.apelido} ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: '(${perfilNome})',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6.0),
                              child: Icon(Icons.circle, size: 10, color: statusColor),
                            ),
                          ),
                        ],
                      ),
                    ),

                    subtitle: Text(
                      'Status: $statusText\n${usuario.email}\nTel: ${usuario.telefone ?? 'N/A'}',
                    ),
                    isThreeLine: true,

                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAtivo ? Icons.person : Icons.person_off,
                          color: statusColor,
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_ios, size: 16),
                      ],
                    ),

                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => DetalhesUsuarioScreen(
                            usuarioId: usuario.id!,
                          ),
                        ),
                      );
                      setState(() {
                        _usuariosFuture = _loadUsuarios();
                      });
                    },
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