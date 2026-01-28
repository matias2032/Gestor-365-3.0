import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConectividadeService {
  static final ConectividadeService instance = ConectividadeService._internal();
  ConectividadeService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  // Estado
  bool _isOnline = true;
  bool _modoOfflineManual = false;
  DateTime? _ultimaMudanca;
  DateTime? _ultimaSyncCompleta;
  
  // Callbacks (agora recebe 2 parâmetros: isOnline, forcarSync)
  final List<Function(bool, bool)> _listeners = [];
  
  // Debounce
  Timer? _debounceTimer;
  static const Duration _debounceDelay = Duration(seconds: 3); // 🔥 REDUZIDO para 3s

  // Getters
  bool get isOnline => _isOnline;
  bool get modoOfflineManual => _modoOfflineManual;
  DateTime? get ultimaMudanca => _ultimaMudanca;
  DateTime? get ultimaSyncCompleta => _ultimaSyncCompleta;

  /// Inicializar serviço
  Future<void> inicializar() async {
    // Carregar última sync completa do SharedPreferences
    await _carregarUltimaSyncCompleta();
    
    final result = await _connectivity.checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);
    _ultimaMudanca = DateTime.now();
    
    print('🌐 Conectividade inicial: ${_isOnline ? "ONLINE ✅" : "OFFLINE ❌"}');
    
    if (_ultimaSyncCompleta != null) {
      final minutos = DateTime.now().difference(_ultimaSyncCompleta!).inMinutes;
      print('📊 Última sync completa: há $minutos minutos');
    } else {
      print('📊 Nenhuma sync completa registrada');
    }
    
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
    );
  }

  /// Handle mudança de conectividade COM DEBOUNCE
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final novoEstado = !results.contains(ConnectivityResult.none);
    
    // Apenas processar se realmente mudou
    if (novoEstado != _isOnline) {
      print('🔄 Mudança detectada: ${novoEstado ? "ONLINE ✅" : "OFFLINE ❌"}');
      
      _debounceTimer?.cancel();
      
      // 🔥 OFFLINE: debounce de 3s (evitar falsos positivos)
      // 🔥 ONLINE: aplicar imediatamente
      if (!novoEstado) {
        _debounceTimer = Timer(_debounceDelay, () {
          _aplicarMudanca(novoEstado);
        });
      } else {
        _aplicarMudanca(novoEstado);
      }
    }
  }

  /// Aplicar mudança de estado
  void _aplicarMudanca(bool novoEstado) {
    final estadoAnterior = _isOnline;
    _isOnline = novoEstado;
    _ultimaMudanca = DateTime.now();
    
    // Limpar modo offline manual quando volta online
    if (_isOnline) {
      _modoOfflineManual = false;
    }
    
    print('✅ Estado atualizado: ${_isOnline ? "ONLINE" : "OFFLINE"}');
    
    // 🔥 DECISÃO INTELIGENTE: Quando forçar sync completo?
    bool forcarSyncCompleto = false;
    
    if (novoEstado && !estadoAnterior) {
      // Voltou online após estar offline
      final agora = DateTime.now();
      
      if (_ultimaSyncCompleta == null) {
        // Primeira vez - sempre sincronizar
        forcarSyncCompleto = true;
        print('🔄 Primeira sync - forçando sincronização completa');
      } else {
        final minutosSemSync = agora.difference(_ultimaSyncCompleta!).inMinutes;
        
        // 🔥 REGRA: Só sincronizar se passou mais de 30 minutos
        forcarSyncCompleto = minutosSemSync > 30;
        
        if (forcarSyncCompleto) {
          print('🔄 Passou $minutosSemSync min sem sync - forçando sincronização');
        } else {
          print('✅ Última sync há $minutosSemSync min - dados ainda válidos');
        }
      }
    }
    
    // 🔥 NOTIFICAR LISTENERS COM FLAG DE FORÇAR SYNC
    for (var listener in _listeners) {
      try {
        listener(_isOnline, forcarSyncCompleto);
      } catch (e) {
        print('⚠️ Erro ao notificar listener: $e');
      }
    }
  }

  /// Adicionar listener (recebe 2 parâmetros agora)
  void addListener(Function(bool isOnline, bool forcarSync) callback) {
    _listeners.add(callback);
  }

  /// Remover listener
  void removeListener(Function(bool, bool) callback) {
    _listeners.remove(callback);
  }

  /// Activar modo offline manual
  void activarModoOfflineManual() {
    _modoOfflineManual = true;
    print('📴 Modo offline manual ATIVADO');
  }

  /// Marcar que foi feita uma sync completa
  Future<void> marcarSyncCompleta() async {
    _ultimaSyncCompleta = DateTime.now();
    
    // 🔥 PERSISTIR NO SHARED PREFERENCES
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ultima_sync_completa', _ultimaSyncCompleta!.toIso8601String());
    
    print('✅ Sync completa registrada: ${_ultimaSyncCompleta}');
  }

  /// Carregar última sync completa do SharedPreferences
  Future<void> _carregarUltimaSyncCompleta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ultimaSyncStr = prefs.getString('ultima_sync_completa');
      
      if (ultimaSyncStr != null && ultimaSyncStr.isNotEmpty) {
        _ultimaSyncCompleta = DateTime.parse(ultimaSyncStr);
        print('📥 Última sync carregada: $_ultimaSyncCompleta');
      }
    } catch (e) {
      print('⚠️ Erro ao carregar última sync: $e');
      _ultimaSyncCompleta = null;
    }
  }

  /// Forçar verificação de conectividade
  Future<bool> verificarConectividade() async {
    final result = await _connectivity.checkConnectivity();
    final online = !result.contains(ConnectivityResult.none);
    
    if (online != _isOnline) {
      _aplicarMudanca(online);
    }
    
    return online;
  }

  /// Limpar histórico de sync (útil para testes ou reset)
  Future<void> limparHistoricoSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ultima_sync_completa');
    _ultimaSyncCompleta = null;
    print('🗑️ Histórico de sync limpo');
  }

  /// Dispose
  void dispose() {
    _connectivitySubscription?.cancel();
    _debounceTimer?.cancel();
    _listeners.clear();
    print('🔌 ConectividadeService encerrado');
  }
}