// lib/screens/splash_screen.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// Serviços
import '../services/base_de_dados.dart';
import '../services/supabase_sync_service.dart';
import '../services/sessao_service.dart';
import '../services/notificacao_estoque_service.dart';
import '../services/estoque_alerta_service.dart';
import '../providers/theme_provider.dart';
import 'package:gestao_bar_pos/firebase_options.dart';
import '../services/push_notification_service.dart';
import '../services/conectividade_service.dart';
import '../widgets/conectividade_dialog.dart';

// Telas
import 'tela_login.dart';
import 'dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Controllers de Animação
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  // Estado de Progresso
  double _progress = 0.0;
  String _statusMessage = 'Iniciando...';
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeApp();
  }

  void _setupAnimations() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
  }

Future<void> _initializeApp() async {
  try {
    // 1️⃣ Inicializar Serviço de Conectividade (5%)
    await _updateProgress(0.05, 'Verificando conexão...');
    await ConectividadeService.instance.inicializar();
    final isOnline = ConectividadeService.instance.isOnline;
    print('🌐 Conectividade: ${isOnline ? "ONLINE" : "OFFLINE"}');
    await Future.delayed(const Duration(milliseconds: 300));

    // 🔥 NOVO: Se offline, mostrar dialog APÓS animação da splash
    if (!isOnline && mounted) {
      await _controller.forward(); // Garantir que animação termine
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        await ConectividadeDialog.mostrar(
          context,
          isPreSplash: true,
          onReconectar: () {
            // Reiniciar splash
            setState(() {
              _hasError = false;
              _progress = 0.0;
            });
            _initializeApp();
          },
          onContinuarOffline: () {
            // Continuar inicialização em modo offline
            _continuarInicializacao(isOnline: false);
          },
        );
        return; // Interromper fluxo até utilizador decidir
      }
    }

    // Se online OU se utilizador escolheu continuar offline
    await _continuarInicializacao(isOnline: isOnline);
    
  } catch (e, stackTrace) {
    setState(() {
      _hasError = true;
      _errorMessage = 'Erro ao inicializar o aplicativo';
    });
    print('❌ Erro: $e\n$stackTrace');
  }
}

// 🔥 NOVO MÉTODO: Continuar inicialização
Future<void> _continuarInicializacao({required bool isOnline}) async {
  // 2️⃣ Inicializar Timezone (15%)
  await _updateProgress(0.15, 'Configurando fuso horário...');
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Africa/Maputo'));
  await Future.delayed(const Duration(milliseconds: 200));

  // 3️⃣ Inicializar Supabase (30%)
  await _updateProgress(0.30, 'Conectando ao servidor...');
  await Supabase.initialize(
    url: 'https://uwwzjvovxisakkugzxsh.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3d3pqdm92eGlzYWtrdWd6eHNoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYxMjkzMjMsImV4cCI6MjA4MTcwNTMyM30.E3qQ0oxLTLcPphUdHTZmUtjIgzQD651aS8ZxstVvc_Y',
  );
  print('✅ Supabase inicializado');
  await Future.delayed(const Duration(milliseconds: 400));

// 4️⃣ Inicializar Firebase/FCM (40%) - CONDICIONALMENTE
await _updateProgress(0.40, 'Configurando notificações push...');
if (isOnline) {
  try {
    await PushNotificationService.instance.inicializar();
    print('✅ FCM inicializado');
  } catch (e) {
    print('⚠️ FCM não disponível: $e');
  }
} else {
  print('⏭️ FCM pulado (modo offline)');
}
await Future.delayed(const Duration(milliseconds: 300));

  // 5️⃣ Inicializar Banco de Dados Local (55%)
  await _updateProgress(0.55, 'Preparando banco de dados...');
  await DatabaseService.instance.database;
  print('📦 Banco de dados pronto');
  await Future.delayed(const Duration(milliseconds: 300));

  // 6️⃣ Inicializar Serviço de Sincronização (70%)
  await _updateProgress(0.70, 
    isOnline ? 'Sincronizando dados...' : 'Modo offline ativado');
  
  if (isOnline) {
    try {
      await SupabaseSyncService.instance.initialize();
      print('✅ Sincronização inicializada');
    } catch (e) {
      print('⚠️ Erro ao sincronizar: $e');
    }
  }
  await Future.delayed(const Duration(milliseconds: 400));

  // 7️⃣ Inicializar Tema (80%)
  await _updateProgress(0.80, 'Carregando preferências...');
  await ThemeProvider().initTheme();
  await Future.delayed(const Duration(milliseconds: 200));

  // 8️⃣ Inicializar Notificações Locais (87%)
  await _updateProgress(0.87, 'Configurando alertas...');
  await NotificacaoEstoqueService.instance.inicializar();
  await EstoqueAlertaService.instance.inicializar();
  await Future.delayed(const Duration(milliseconds: 300));

  // 9️⃣ Verificar Sessão COM VALIDAÇÃO
  await _updateProgress(0.95, 'Verificando sessão...');
  await SessaoService.instance.inicializarSessao();
  
  bool sessaoValida = false;
  if (SessaoService.instance.isLogado) {
    sessaoValida = await SessaoService.instance.validarSessao();
    if (!sessaoValida) {
      print('⚠️ Sessão inválida detectada - requer novo login');
    }
  }
  
  await Future.delayed(const Duration(milliseconds: 300));

  // 🔟 Finalizar (100%)
  await _updateProgress(1.0, sessaoValida ? 'Bem-vindo de volta! 🎉' : 'Pronto! 🎉');
  await Future.delayed(const Duration(milliseconds: 800));

  // 🚀 Navegar
  if (mounted) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => sessaoValida
            ? const DashboardVendasScreen()
            : const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }
}

  Future<void> _updateProgress(double progress, String message) async {
    if (!mounted) return;
    
    setState(() {
      _progress = progress;
      _statusMessage = message;
    });
    
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.deepOrange,
              Colors.deepOrange.withOpacity(0.8),
              Colors.amber.shade700,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // 🎯 Logo/Branding Animado
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: _buildLogo(),
                    ),
                  ),

                  const SizedBox(height: 60),

                  // 📝 Texto "Criado por Matias Matavel"
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildCredits(),
                    ),
                  ),

                  const Spacer(),

                  // 📊 Barra de Progresso
                  if (!_hasError) _buildProgressSection(),

                  // ❌ Mensagem de Erro
                  if (_hasError) _buildErrorSection(),

                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.restaurant_menu,
            size: 60,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        
        const Text(
          'Bar Digital POS',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        
        Text(
          'Sistema de Gestão',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withOpacity(0.9),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCredits() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: const Text(
        'Criado por Matias Matavel',
        style: TextStyle(
          fontSize: 16,
          color: Colors.white,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 8,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              tween: Tween<double>(begin: 0, end: _progress),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white.withOpacity(0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _statusMessage,
            key: ValueKey<String>(_statusMessage),
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        
        const SizedBox(height: 8),
        Text(
          '${(_progress * 100).toInt()}%',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.7),
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorSection() {
    return Column(
      children: [
        const Icon(
          Icons.error_outline,
          color: Colors.white,
          size: 48,
        ),
        const SizedBox(height: 16),
        Text(
          _errorMessage,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Verifique sua conexão e tente novamente',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _hasError = false;
              _progress = 0.0;
              _errorMessage = '';
            });
            _initializeApp();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.deepOrange,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: const Text(
            'Tentar Novamente',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}