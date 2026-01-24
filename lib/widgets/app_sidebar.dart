// lib/widgets/app_sidebar.dart (VERSÃO COM CONTROLE DE ACESSO POR PERFIL)

import 'package:flutter/material.dart';
import 'dart:async';
import '../services/sessao_service.dart';
import '../services/pedido_contador_service.dart';
// import '../widgets/theme_toggle_widget.dart';
import '../services/servico_logs.dart';
import '../widgets/estoque_badge.dart';

class AppSidebar extends StatefulWidget {
  final String currentRoute;
  
  const AppSidebar({
    super.key,
    required this.currentRoute,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> with SingleTickerProviderStateMixin {
  bool _showUserMenu = false;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  
  int _contadorPedidos = 0;
  StreamSubscription<int>? _contadorSubscription;
  final PedidoContadorService _contadorService = PedidoContadorService.instance;

 @override
void initState() {
  super.initState();
  _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(
    CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
  );
  
  // 🔥 CARREGAR CONTADOR DO USUÁRIO LOGADO
  _carregarContadorDoUsuario();
  
  _contadorPedidos = _contadorService.contadorAtual;
  _contadorSubscription = _contadorService.contadorStream.listen((novoValor) {
    if (mounted) {
      setState(() {
        _contadorPedidos = novoValor;
      });
    }
  });
}

Future<void> _carregarContadorDoUsuario() async {
  final usuario = SessaoService.instance.usuarioAtual;
  if (usuario != null) {
    // 🔥 NOVO: Usar método com cache inteligente
    await _contadorService.recarregarSeNecessario();
  }
}

  @override
  void dispose() {
    _animationController.dispose();
    _contadorSubscription?.cancel();
    super.dispose();
  }

  void _toggleUserMenu() {
    setState(() {
      _showUserMenu = !_showUserMenu;
      if (_showUserMenu) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  // 🔥 NOVO: Verifica se o usuário tem permissão para acessar a rota
  bool _temPermissao(String route) {
    final usuario = SessaoService.instance.usuarioAtual;
    if (usuario == null) return false;

    final idPerfil = usuario.idPerfil;

    // idperfil=1 (Administrador) tem acesso a tudo
    if (idPerfil == 1) return true;

    // idperfil=2 (Gerente) tem acesso a: movimentos estoque, logs, gerenciar usuários e histórico pedidos
    if (idPerfil == 2) {
      return [
        '/movimentos_estoque',
        '/logs',
        '/gerenciar_usuarios',
        '/historico_pedidos',
        '/dashboard',
      ].contains(route);
    }

    // idperfil=3 (Funcionário) tem acesso a: criar pedidos, gerenciar categorias, gerenciar produtos
    if (idPerfil == 3) {
      return [
        '/menu',
        '/gerenciar_categorias',
        '/gerenciar_produtos',
        '/dashboard',
      ].contains(route);
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final usuario = SessaoService.instance.usuarioAtual;
    
    if (usuario == null) {
      return const SizedBox.shrink();
    }

    return Drawer(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerHeader(usuario),
                
                _buildMenuItem(
                  icon: Icons.dashboard,
                  title: 'Dashboard',
                  route: '/dashboard',
                ),
                // const Divider(),
                // ThemeToggleWidget(showLabel: true),
                 
                // 🔥 CONTROLE DE ACESSO: Criar Pedido (Funcionário e Admin)
                if (_temPermissao('/menu'))
                  _buildMenuItemComContador(
                    icon: Icons.shopping_cart,
                    title: 'Criar Pedido',
                    route: '/menu',
                    contador: _contadorPedidos,
                  ),
                
                // 🔥 CONTROLE DE ACESSO: Gerenciar Categorias (Funcionário e Admin)
                if (_temPermissao('/gerenciar_categorias'))
                  _buildMenuItem(
                    icon: Icons.category,
                    title: 'Gerenciar Categorias',
                    route: '/gerenciar_categorias',
                  ),
                
                
if (_temPermissao('/gerenciar_produtos'))
  _buildMenuItem(
    icon: Icons.fastfood,
    title: 'Gerenciar Produtos',
    route: '/gerenciar_produtos',
    usarBadge: true, // 🔥 NOVO PARÂMETRO
  ),
                
                // 🔥 CONTROLE DE ACESSO: Gerenciar Usuários (Gerente e Admin)
                if (_temPermissao('/gerenciar_usuarios'))
                  _buildMenuItem(
                    icon: Icons.people,
                    title: 'Gerenciar Usuários',
                    route: '/gerenciar_usuarios',
                  ),
                
                // 🔥 CONTROLE DE ACESSO: Histórico de Pedidos (Gerente e Admin)
                if (_temPermissao('/historico_pedidos'))
                  _buildMenuItem(
                    icon: Icons.history,
                    title: 'Histórico de Pedidos',
                    route: '/historico_pedidos',
                  ),
                
                // 🔥 CONTROLE DE ACESSO: Logs do Sistema (Gerente e Admin)
                if (_temPermissao('/logs'))
                  _buildMenuItem(
                    icon: Icons.list_alt,
                    title: 'Logs do Sistema',
                    route: '/logs',
                  ),

                // 🔥 CONTROLE DE ACESSO: Movimentos de Estoque (Gerente e Admin)
                if (_temPermissao('/movimentos_estoque'))
                  _buildMenuItem(
                    icon: Icons.inventory,
                    title: 'Movimentos de Estoque',
                    route: '/movimentos_estoque',
                  ),

                  //   if (_temPermissao('/corrigir_imagens'))
                  // _buildMenuItem(
                  //   icon: Icons.list_alt,
                  //   title: 'Corrigir Imagens',
                  //   route: '/corrigir_imagens',
                  // ),
              ],
            ),
          ),
          
          _buildUserSection(usuario),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader(usuario) {
    return DrawerHeader(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.deepOrange,
            Colors.deepOrange.shade700,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Hero(
            tag: 'user_avatar_${usuario.id}',
            child: CircleAvatar(
              radius: 32,
              backgroundColor: Colors.white,
              child: Text(
                usuario.nome![0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 36,
                  color: Colors.deepOrange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${usuario.nome} ${usuario.apelido}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _getPerfilName(usuario.idPerfil),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
  required IconData icon,
  required String title,
  required String route,
  bool usarBadge = false, // 🔥 NOVO PARÂMETRO
}) {
  final isSelected = widget.currentRoute == route;
  
  Widget iconWidget = Icon(
    icon,
    color: isSelected ? Colors.deepOrange : Colors.grey[700],
  );
  
  // 🔥 APLICAR BADGE SE NECESSÁRIO
  if (usarBadge) {
    iconWidget = EstoqueBadge(child: iconWidget);
  }
  
  return ListTile(
    leading: iconWidget,
    title: Text(
      title,
      style: TextStyle(
        color: isSelected ? Colors.deepOrange : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    ),
    selected: isSelected,
    selectedTileColor: Colors.deepOrange.withOpacity(0.1),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    onTap: () {
      Navigator.pop(context);
      if (!isSelected) {
        Navigator.pushReplacementNamed(context, route);
      }
    },
  );
}


  Widget _buildMenuItemComContador({
    required IconData icon,
    required String title,
    required String route,
    required int contador,
  }) {
    final isSelected = widget.currentRoute == route;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Colors.deepOrange : Colors.grey[700],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.deepOrange : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (contador > 0)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Text(
                '$contador',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      selected: isSelected,
      selectedTileColor: Colors.deepOrange.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      onTap: () {
        Navigator.pop(context);
        if (!isSelected) {
          Navigator.pushReplacementNamed(context, route);
        }
      },
    );
  }

  Widget _buildUserSection(usuario) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.bottomCenter,
            child: _showUserMenu
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildUserMenuItem(
                          icon: Icons.person,
                          title: 'Alterar Dados',
                          color: Colors.blue,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/editar_usuario');
                          },
                        ),
                        Divider(height: 1, color: Colors.grey[200]),
                        _buildUserMenuItem(
                          icon: Icons.lock,
                          title: 'Alterar Senha',
                          color: Colors.orange,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/alterar_senha');
                          },
                        ),
                        Divider(height: 1, color: Colors.grey[200]),
                        _buildUserMenuItem(
                          icon: Icons.logout,
                          title: 'Sair',
                          color: Colors.red,
                          onTap: () => _confirmarLogout(context),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleUserMenu,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.deepOrange,
                      child: Text(
                        usuario.nome![0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${usuario.nome} ${usuario.apelido}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            usuario.email!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    RotationTransition(
                      turns: _rotationAnimation,
                      child: Icon(
                        Icons.expand_less,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserMenuItem({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: title == 'Sair' ? Colors.red : Colors.black87,
          fontSize: 14,
        ),
      ),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
    );
  }

  Future<void> _confirmarLogout(BuildContext context) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 12),
            Text('Confirmar Saída'),
          ],
        ),
        content: const Text('Tem certeza que deseja sair da sua conta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirmado == true) {
      final usuario = SessaoService.instance.usuarioAtual;
      
      if (usuario != null) {
        await ServicoLogs.instance.registrarLogout(
          usuario.id!,
          '${usuario.nome} ${usuario.apelido}',
        );
      }
      
      _contadorService.resetar();
      SessaoService.instance.limparSessao();
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  String _getPerfilName(int? idPerfil) {
    switch (idPerfil) {
      case 1:
        return 'Administrador';
      case 2:
        return 'Gerente';
      case 3:
        return 'Funcionário';
      case 4:
        return 'Cliente';
      default:
        return 'Usuário';
    }
  }
}
