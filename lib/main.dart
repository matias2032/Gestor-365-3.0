// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Serviços
import 'services/sessao_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; 

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
import 'screens/configuracoes_impressora_screen.dart';
import 'widgets/conectividade_dialog.dart';
import 'services/supabase_sync_service.dart';
import 'package:flutter/foundation.dart'; 
import 'dart:async';

// 🔥 HANDLER BACKGROUND (TOP-LEVEL)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('📬 Background: ${message.messageId}');
} 

void main() async {
  // Capturar TODOS os erros não tratados
  FlutterError.onError = (FlutterErrorDetails details) {
    print('🔴 FlutterError: ${details.exception}');
    print('🔴 Stack: ${details.stack}');
  };

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

       if (!kIsWeb && (
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS
    )) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    print('✅ 1. WidgetsFlutterBinding OK');

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    print('✅ 2. Orientações OK');

    // Firebase APENAS em plataformas suportadas
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
        FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
          if (message != null) _agendarProcessamentoNotificacaoInicial(message);
        });
        print('✅ 3. Firebase OK');
      } catch (e) {
        print('⚠️ Firebase erro: $e');
      }
    } else {
      print('⏭️ 3. Firebase pulado (Windows)');
    }

    print('✅ 4. Chamando runApp...');
    runApp(const MyApp());
    print('✅ 5. runApp OK');

  }, (error, stack) {
    print('🔴 ERRO FATAL: $error');
    print('🔴 STACK: $stack');
  });
}

// 🔥 Processar notificação inicial após delay
void _agendarProcessamentoNotificacaoInicial(RemoteMessage message) {
  // Aguardar 2 segundos para o app inicializar completamente (splash + validação de sessão)
  Future.delayed(const Duration(seconds: 2), () async {
    await PushNotificationService.instance.processarNotificacaoInicial(message);
  });
}

// 🔥 ATUALIZADO: Lifecycle Observer integrado com PushNotificationService
class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('🔄 Lifecycle: $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        // Marcar app como ativo na sessão
        SessaoService.instance.marcarAppAtivo();
        
        // 🔥 DELEGADO: O PushNotificationService já limpa notificações via _AppLifecycleListener
        // Não precisamos duplicar essa lógica aqui
        print('✅ App retomado - notificações sendo limpas pelo PushNotificationService');
        break;
        
      case AppLifecycleState.paused:
        print('⏸️ App pausado');
        break;
        
      case AppLifecycleState.inactive:
        print('💤 App inativo');
        break;
        
      case AppLifecycleState.detached:
        print('🔌 App desconectado');
        break;
        
      default:
        break;
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class ConectividadeListener {
  static bool _dialogAberto = false;
  static bool _processandoReconexao = false;

  static void inicializar() {
    ConectividadeService.instance.addListener((isOnline, forcarSync) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onConnectivityChange(isOnline, forcarSync);
      });
    });
  }

  static void _onConnectivityChange(bool isOnline, bool forcarSync) async {
    final context = MyApp.navigatorKey.currentContext;
    
    if (isOnline) {
      _mostrarSnackBar(
        '🌐 Conexão restaurada!',
        Colors.green,
        Icons.wifi,
      );
      _dialogAberto = false;

      if (forcarSync && !_processandoReconexao) {
        _processandoReconexao = true;
        try {
          await _sincronizarAposReconexao();
        } catch (e) {
          _mostrarSnackBar(
            '⚠️ Erro na sincronização: ${e.toString().split(':').first}',
            Colors.orange,
            Icons.warning,
          );
        } finally {
          _processandoReconexao = false;
        }
      }
      return;
    }

    // --- Lógica Offline ---
    if (context == null || !context.mounted) return;
    
    final rotaAtual = ModalRoute.of(context)?.settings.name;
    if (ConectividadeService.instance.modoOfflineManual || 
        _dialogAberto || 
        ['/splash', '/', '/primeira_troca_senha'].contains(rotaAtual)) {
      return;
    }

    _dialogAberto = true;
    try {
      await ConectividadeDialog.mostrar(
        context,
        isPreSplash: false,
        onReconectar: () async {
          _dialogAberto = false;
          if (SessaoService.instance.isLogado) {
            final sessaoValida = await SessaoService.instance.validarSessao();
            if (!sessaoValida && context.mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          }
        },
        onContinuarOffline: () {
          _dialogAberto = false;
          _mostrarSnackBar(
            '✈️ Modo offline ativado.',
            Colors.orange,
            Icons.airplanemode_active,
          );
        },
      );
    } catch (e) {
      _dialogAberto = false;
      _mostrarSnackBar('📵 Sem conexão - Modo offline', Colors.red, Icons.wifi_off);
    }
  }

  static void _mostrarSnackBar(
    String mensagem,
    Color cor,
    IconData icone,
  ) {
    MyApp.messengerKey.currentState?.hideCurrentSnackBar();
    MyApp.messengerKey.currentState?.showSnackBar(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static Future<void> _sincronizarAposReconexao() async {
    final syncService = SupabaseSyncService.instance;
    if (syncService.pendingOperations > 0) {
      await syncService.syncOfflineQueue();
    }
    if (syncService.pendingOperations == 0) {
      await syncService.syncAll();
      ConectividadeService.instance.marcarSyncCompleta();
    }
  }
}

class _MyAppState extends State<MyApp> {
  late final AppLifecycleObserver _lifecycleObserver;
    late final ThemeProvider _themeProvider;
  @override
  void initState() {
    super.initState();
     _themeProvider = ThemeProvider();
    _lifecycleObserver = AppLifecycleObserver();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ConectividadeListener.inicializar();
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
       
    return AnimatedBuilder(
       animation: _themeProvider,
      builder: (context, child) {
        return MaterialApp(
          title: 'Gestor 365',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: _themeProvider.themeMode,
          navigatorKey: MyApp.navigatorKey,
          scaffoldMessengerKey: MyApp.messengerKey,
          initialRoute: '/splash',
          onGenerateRoute: (settings) {
            const rotasPublicas = [
              '/splash',
              '/',
              '/primeira_troca_senha'
            ];
            
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

                case '/configuracoes_impressora':
                return MaterialPageRoute(
                  builder: (_) => const ConfiguracoesImpressoraScreen(),
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