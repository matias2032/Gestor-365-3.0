// lib/main.dart

import 'package:flutter/material.dart';

// Serviços
import 'services/sessao_service.dart';
import 'services/notificacao_estoque_service.dart';
import 'services/estoque_alerta_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';

// Tema
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';

// Telas
import 'screens/splash_screen.dart';
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
import 'screens/finalizar_pedido.dart';
import 'screens/detalhes_produto.dart';
import 'screens/pedidos_por_finalizar.dart';
import 'screens/editar_usuario.dart';
import 'screens/alterar_senha.dart';
import 'screens/historico_pedidos.dart';
import 'screens/logs.dart';
import 'screens/movimentos_estoque.dart';
import 'screens/primeira_troca_senha.dart';
import 'screens/corrigir_imagens_screen.dart';
import 'services/conectividade_service.dart';
import 'widgets/conectividade_dialog.dart';
import 'widgets/conectividade_indicator.dart';
import 'services/supabase_sync_service.dart';

// 🔥 HANDLER BACKGROUND (TOP-LEVEL)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('📬 Background: ${message.messageId}');
} 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    print('✅ Firebase inicializado');
    
    // 🔥 Verificar se app foi aberto por notificação (quando estava fechado)
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('📬 App aberto por notificação (terminated): ${message.data}');
        // Agendar processamento após app inicializar
        _agendarProcessamentoNotificacaoInicial(message);
      }
    });
    
  } catch (e) {
    print('⚠️ Erro Firebase: $e');
  }
  
  runApp(const MyApp());
}

// 🔥 Processar notificação inicial após delay
void _agendarProcessamentoNotificacaoInicial(RemoteMessage message) {
  // Aguardar 2 segundos para o app inicializar completamente (splash + validação de sessão)
  Future.delayed(const Duration(seconds: 2), () async {
    await PushNotificationService.instance.processarNotificacaoInicial(message);
  });
}

// 🔥 SIMPLIFICADO: Lifecycle Observer (apenas atualiza timestamp)
class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('🔄 Lifecycle: $state');
    
    if (state == AppLifecycleState.resumed) {
      SessaoService.instance.marcarAppAtivo();
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

// 🔥 SUBSTITUIR a classe ConectividadeListener:

class ConectividadeListener {
  static bool _dialogAberto = false;
  static bool _processandoReconexao = false; // 🔥 NOVO: Evitar múltiplas sincronizações
  
  static void inicializar(BuildContext context) {
    ConectividadeService.instance.addListener((isOnline, forcarSync) {
      // 🔥 CRÍTICO: Usar addPostFrameCallback para garantir que MaterialApp está montado
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _onConnectivityChange(context, isOnline, forcarSync);
        }
      });
    });
  }
  
  static void _onConnectivityChange(
    BuildContext context, 
    bool isOnline, 
    bool forcarSync,
  ) async {
    final service = ConectividadeService.instance;
    
    // ==========================================
    // VOLTOU ONLINE
    // ==========================================
    if (isOnline) {
      _mostrarSnackBar(
        context,
        '🌐 Conexão restaurada!',
        Colors.green,
        Icons.wifi,
      );
      _dialogAberto = false;
      
      // 🔥 NOVO: Sincronização inteligente COM PROTEÇÃO contra múltiplas execuções
      if (forcarSync && !_processandoReconexao) {
        _processandoReconexao = true;
        
        print('🔄 Forçando sincronização completa (passou >30min offline)');
        
        try {
          await _sincronizarAposReconexao();
        } catch (e) {
          print('❌ Erro na sincronização: $e');
          
          if (context.mounted) {
            _mostrarSnackBar(
              context,
              '⚠️ Erro na sincronização: ${e.toString().split(':').first}',
              Colors.orange,
              Icons.warning,
            );
          }
        } finally {
          _processandoReconexao = false;
        }
      } else if (!forcarSync) {
        print('✅ Conexão restaurada - dados recentes, sem necessidade de sync');
      } else {
        print('⏳ Sincronização já em andamento...');
      }
      
      return;
    }
    
    // ==========================================
    // FICOU OFFLINE
    // ==========================================
    final rotaAtual = ModalRoute.of(context)?.settings.name;
    
    // Não mostrar dialog em rotas públicas ou se já está aberto
    if (service.modoOfflineManual || 
        _dialogAberto || 
        rotaAtual == '/splash' ||
        rotaAtual == '/' ||
        rotaAtual == '/primeira_troca_senha') {
      return;
    }
    
    // 🔥 VALIDAR CONTEXTO antes de mostrar dialog
    if (!context.mounted) {
      print('⚠️ Contexto desmontado - não é possível mostrar dialog');
      return;
    }
    
    _dialogAberto = true;
    
    try {
      await ConectividadeDialog.mostrar(
        context,
        isPreSplash: false,
        onReconectar: () async {
          _dialogAberto = false;
          
          // Validar sessão se estiver logado
          if (SessaoService.instance.isLogado) {
            final sessaoValida = await SessaoService.instance.validarSessao();
            
            if (!sessaoValida && context.mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/',
                (route) => false,
              );
            }
          }
        },
        onContinuarOffline: () {
          _dialogAberto = false;
          _mostrarSnackBar(
            context,
            '✈️ Modo offline ativado. Funcionalidades limitadas.',
            Colors.orange,
            Icons.airplanemode_active,
          );
        },
      );
    } catch (e) {
      print('❌ Erro ao mostrar dialog: $e');
      _dialogAberto = false;
      
      // Fallback: mostrar apenas SnackBar
      if (context.mounted) {
        _mostrarSnackBar(
          context,
          '📵 Sem conexão - Modo offline',
          Colors.red,
          Icons.wifi_off,
        );
      }
    }
  }
  
  // 🔥 MÉTODO DE SINCRONIZAÇÃO INTELIGENTE
  static Future<void> _sincronizarAposReconexao() async {
    print('🔄 Iniciando sincronização pós-reconexão...');
    
    final syncService = SupabaseSyncService.instance;
    
    // 1. Processar fila offline primeiro
    if (syncService.pendingOperations > 0) {
      print('📤 Processando ${syncService.pendingOperations} operações offline...');
      await syncService.syncOfflineQueue();
    }
    
    // 2. Sincronização completa apenas se fila vazia
    if (syncService.pendingOperations == 0) {
      print('🔄 Iniciando sincronização completa...');
      await syncService.syncAll();
      
      // Marcar sync completa
      ConectividadeService.instance.marcarSyncCompleta();
      print('✅ Sincronização completa concluída');
    } else {
      print('⚠️ Ainda há ${syncService.pendingOperations} operações pendentes');
    }
  }
  
  static void _mostrarSnackBar(
    BuildContext context,
    String mensagem,
    Color cor,
    IconData icone,
  ) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).hideCurrentSnackBar(); // 🔥 LIMPAR ANTERIORES
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icone, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                mensagem,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

class _MyAppState extends State<MyApp> {
  late final AppLifecycleObserver _lifecycleObserver;
  
  @override
  void initState() {
    super.initState();
    _lifecycleObserver = AppLifecycleObserver();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    
    // 🔥 NOVO: Aguardar primeiro frame para inicializar listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ConectividadeListener.inicializar(context);
      }
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    ConectividadeService.instance.dispose();
    super.dispose();
  }

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
          navigatorKey: MyApp.navigatorKey,
          initialRoute: '/splash',
          onGenerateRoute: (settings) {
            const rotasPublicas = [
              '/splash',
              '/',
              '/primeira_troca_senha'
            ];
            
            // 🔥 Validar sessão antes de permitir rotas protegidas
            if (!rotasPublicas.contains(settings.name)) {
              if (!SessaoService.instance.isLogado) {
                return MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                  settings: RouteSettings(
                    name: '/',
                    arguments: settings.name,
                  ),
                );
              }
            }

            switch (settings.name) {
              case '/splash':
                return MaterialPageRoute(
                  builder: (_) => const SplashScreen(),
                );

              case '/':
                if (SessaoService.instance.isLogado) {
                  return MaterialPageRoute(
                    builder: (_) => const DashboardVendasScreen(),
                  );
                }
                return MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                );

              case '/primeira_troca_senha':
                return MaterialPageRoute(
                  builder: (_) => const PrimeiraTrocaSenhaScreen(),
                );

              case '/dashboard':
                return MaterialPageRoute(
                  builder: (_) => const DashboardVendasScreen(),
                );

              case '/gerenciar_usuarios':
                return MaterialPageRoute(
                  builder: (_) => const UsuarioListScreen(),
                );
              
              case '/cadastro_usuario':
                return MaterialPageRoute(
                  builder: (_) => const UsuarioFormScreen(),
                );

              case '/editar_usuario':
                return MaterialPageRoute(
                  builder: (_) => const EditarUsuarioScreen(),
                );
              
              case '/alterar_senha':
                return MaterialPageRoute(
                  builder: (_) => const AlterarSenhaScreen(),
                );

              case '/corrigir_imagens':
                return MaterialPageRoute(
                  builder: (_) => const CorrigirImagensScreen(),
                );

              case '/gerenciar_categorias':
                return MaterialPageRoute(
                  builder: (_) => const GerenciarCategoriasScreen(),
                );
              
              case '/cadastrar_categoria':
                return MaterialPageRoute(
                  builder: (_) => const CadastrarCategoriaScreen(),
                );
              
              case '/editar_categoria':
                final categoriaId = settings.arguments as int?;
                if (categoriaId != null) {
                  return MaterialPageRoute(
                    builder: (_) => EditarCategoriaScreen(
                      categoriaId: categoriaId,
                    ),
                  );
                }
                return MaterialPageRoute(
                  builder: (_) => const GerenciarCategoriasScreen(),
                );

              case '/gerenciar_produtos':
                return MaterialPageRoute(
                  builder: (_) => const GerenciarProdutosScreen(),
                );
              
              case '/cadastrar_produto':
                return MaterialPageRoute(
                  builder: (_) => const CadastrarProdutoScreen(),
                );
              
              case '/editar_produto':
                final produtoId = settings.arguments as int?;
                if (produtoId != null) {
                  return MaterialPageRoute(
                    builder: (_) => EditarProdutoScreen(
                      produtoId: produtoId,
                    ),
                  );
                }
                return MaterialPageRoute(
                  builder: (_) => const GerenciarProdutosScreen(),
                );
              
              case '/detalhes_produto':
                final produtoId = settings.arguments as int?;
                if (produtoId != null) {
                  return MaterialPageRoute(
                    builder: (_) => DetalhesProdutoScreen(
                      produtoId: produtoId,
                    ),
                  );
                }
                return MaterialPageRoute(
                  builder: (_) => const MenuScreen(),
                );

              case '/menu':
                return MaterialPageRoute(
                  builder: (_) => const MenuScreen(),
                );

              case '/pedidos_por_finalizar':
                return MaterialPageRoute(
                  builder: (_) => const PedidosPorFinalizarScreen(),
                );
              
              case '/finalizar_pedido':
                final pedidoId = settings.arguments as int?;
                if (pedidoId != null) {
                  return MaterialPageRoute(
                    builder: (_) => FinalizarPedidoScreen(
                      pedidoId: pedidoId,
                    ),
                  );
                }
                return MaterialPageRoute(
                  builder: (_) => const PedidosPorFinalizarScreen(),
                );

              case '/historico_pedidos':
                return MaterialPageRoute(
                  builder: (_) => const HistoricoPedidosScreen(),
                );
              
              case '/logs':
                return MaterialPageRoute(
                  builder: (_) => const LogsScreen(),
                );

              case '/movimentos_estoque':
                return MaterialPageRoute(
                  builder: (_) => const MovimentosEstoqueScreen(),
                );

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
                          const Icon(
                            Icons.error_outline,
                            size: 80,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Página não encontrada',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
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