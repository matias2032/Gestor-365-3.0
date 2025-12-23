import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Serviços
import 'services/sessao_service.dart';
import 'services/supabase_sync_service.dart'; // 🔥 Nova importação do Sync

// Tema
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';

// Importa as telas do seu projeto
import 'screens/gerenciar_usuarios.dart'; 
import 'screens/cadastrar_usuario.dart';
import 'screens/tela_login.dart'; 
import 'screens/dashboard.dart';
import 'screens/gerenciar_categorias.dart';
import 'screens/cadastrar_categoria.dart';
import 'screens/editar_categoria.dart';
import 'screens/cadastrar_produto.dart';
import 'screens/editar_produto.dart';
import 'screens/gerenciar_produtos.dart';
import 'screens/menu.dart';
import 'screens/detalhes_pedido.dart';
import 'screens/finalizar_pedido.dart';
import 'screens/detalhes_produto.dart';
import 'screens/pedidos_por_finalizar.dart';
import 'screens/editar_usuario.dart';
import 'screens/alterar_senha.dart';
import 'screens/historico_pedidos.dart';
import 'screens/logs.dart';
import 'screens/movimentos_estoque.dart';
import 'screens/primeira_troca_senha.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ==========================================
  // 🔐 1. INICIALIZAR SUPABASE (CREDENCIAS REAIS)
  // ==========================================
  await Supabase.initialize(
    url: 'https://uwwzjvovxisakkugzxsh.supabase.co',
    // Chave anon pública fornecida:
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3d3pqdm92eGlzYWtrdWd6eHNoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYxMjkzMjMsImV4cCI6MjA4MTcwNTMyM30.E3qQ0oxLTLcPphUdHTZmUtjIgzQD651aS8ZxstVvc_Y');
  print('✅ Supabase inicializado');

  // ==========================================
  // 🔄 2. INICIALIZAR SERVIÇO DE SINCRONIZAÇÃO
  // ==========================================
  try {
    // Inicia o monitoramento de rede e tabelas
 await SupabaseSyncService.instance.initialize();
    print('✅ Serviço de sincronização inicializado');
  } catch (e) {
    print('❌ Erro ao inicializar sincronização: $e');
    // Não paramos o app aqui, pois ele pode rodar offline
  }

  // ==========================================
  // 🎨 3. INICIALIZAR TEMA
  // ==========================================
  await ThemeProvider().initTheme();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = ThemeProvider();
    
    return AnimatedBuilder(
      animation: themeProvider,
      builder: (context, child) {
        return MaterialApp(
          title: 'Bar Digital POS',
          debugShowCheckedModeBanner: false,
          
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          
          initialRoute: '/',
          
          onGenerateRoute: (settings) {
            // 🔥 ROTAS PÚBLICAS (não requerem autenticação)
            const rotasPublicas = ['/', '/primeira_troca_senha'];
            
            // Proteção de rotas (Middleware simples)
            if (!rotasPublicas.contains(settings.name) && !SessaoService.instance.isLogado) {
              return MaterialPageRoute(
                builder: (_) => const LoginScreen(),
                settings: RouteSettings(
                  name: '/',
                  arguments: settings.name,
                ),
              );
            }

            switch (settings.name) {
              // --- ROTA INICIAL ---
              case '/':
                if (SessaoService.instance.isLogado) {
                  return MaterialPageRoute(builder: (_) => const DashboardScreen());
                }
                return MaterialPageRoute(builder: (_) => const LoginScreen());

              // --- RECUPERAÇÃO DE SENHA ---
              case '/primeira_troca_senha':
                return MaterialPageRoute(builder: (_) => const PrimeiraTrocaSenhaScreen());

              // --- DASHBOARD ---
              case '/dashboard':
                return MaterialPageRoute(builder: (_) => const DashboardScreen());

              // --- MÓDULO USUÁRIOS ---
              case '/gerenciar_usuarios':
                return MaterialPageRoute(builder: (_) => const UsuarioListScreen());
              
              case '/cadastro_usuario':
                return MaterialPageRoute(builder: (_) => const UsuarioFormScreen());

              // --- MÓDULO PERFIL DO USUÁRIO ---
              case '/editar_usuario':
                return MaterialPageRoute(builder: (_) => const EditarUsuarioScreen());
              
              case '/alterar_senha':
                return MaterialPageRoute(builder: (_) => const AlterarSenhaScreen());

              // --- MÓDULO CATEGORIAS ---
              case '/gerenciar_categorias':
                return MaterialPageRoute(builder: (_) => const GerenciarCategoriasScreen());
              
              case '/cadastrar_categoria':
                return MaterialPageRoute(builder: (_) => const CadastrarCategoriaScreen());
              
              case '/editar_categoria':
                final categoriaId = settings.arguments as int?;
                if (categoriaId != null) {
                  return MaterialPageRoute(
                    builder: (_) => EditarCategoriaScreen(categoriaId: categoriaId),
                  );
                }
                return MaterialPageRoute(builder: (_) => const GerenciarCategoriasScreen());

              // --- MÓDULO PRODUTOS ---
              case '/gerenciar_produtos':
                return MaterialPageRoute(builder: (_) => const GerenciarProdutosScreen());
              
              case '/cadastrar_produto':
                return MaterialPageRoute(builder: (_) => const CadastrarProdutoScreen());
              
              case '/editar_produto':
                final produtoId = settings.arguments as int?;
                if (produtoId != null) {
                  return MaterialPageRoute(
                    builder: (_) => EditarProdutoScreen(produtoId: produtoId),
                  );
                }
                return MaterialPageRoute(builder: (_) => const GerenciarProdutosScreen());
              
              case '/detalhes_produto':
                final produtoId = settings.arguments as int?;
                if (produtoId != null) {
                  return MaterialPageRoute(
                    builder: (_) => DetalhesProdutoScreen(produtoId: produtoId),
                  );
                }
                return MaterialPageRoute(builder: (_) => const MenuScreen());

              // --- MÓDULO MENU/CARDÁPIO ---
              case '/menu':
                return MaterialPageRoute(builder: (_) => const MenuScreen());

              // --- MÓDULO PEDIDOS ---
              case '/pedidos_por_finalizar':
                return MaterialPageRoute(builder: (_) => const PedidosPorFinalizarScreen());
              
              case '/detalhes_pedido':
                final pedidoId = settings.arguments as int?;
                if (pedidoId != null) {
                  return MaterialPageRoute(
                    builder: (_) => DetalhesPedidoScreen(pedidoId: pedidoId),
                  );
                }
                return MaterialPageRoute(builder: (_) => const PedidosPorFinalizarScreen());
              
              case '/finalizar_pedido':
                final pedidoId = settings.arguments as int?;
                if (pedidoId != null) {
                  return MaterialPageRoute(
                    builder: (_) => FinalizarPedidoScreen(pedidoId: pedidoId),
                  );
                }
                return MaterialPageRoute(builder: (_) => const PedidosPorFinalizarScreen());

              case '/historico_pedidos':
                return MaterialPageRoute(builder: (_) => const HistoricoPedidosScreen());
              
              case '/logs':
                return MaterialPageRoute(builder: (_) => const LogsScreen());

              case '/movimentos_estoque':
                return MaterialPageRoute(
                  builder: (_) => const MovimentosEstoqueScreen()
                );

              // --- ROTA NÃO ENCONTRADA (404) ---
              default:
                return MaterialPageRoute(
                  builder: (context) => Scaffold(
                    appBar: AppBar(
                      title: const Text('Erro 404'),
                      backgroundColor: Colors.red,
                    ),
                    body: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 80, color: Colors.red),
                          const SizedBox(height: 20),
                          const Text(
                            'Página não encontrada',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Rota: ${settings.name}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 30),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/dashboard',
                                (route) => false,
                              );
                            },
                            icon: const Icon(Icons.home),
                            label: const Text('Voltar ao Início'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
            }
          },
        );
      },
    );
  }
}