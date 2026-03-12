import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ConectividadeService {
  static final ConectividadeService instance = ConectividadeService._internal();
  ConectividadeService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  bool _isOnline = true;
  bool _modoOfflineManual = false;
  DateTime? _ultimaMudanca;
  DateTime? _ultimaSyncCompleta;
  
  final List<Function(bool, bool)> _listeners = [];
  Timer? _debounceTimer;
  static const Duration _debounceDelay = Duration(seconds: 3);

  bool get isOnline => _isOnline;
  bool get modoOfflineManual => _modoOfflineManual;
  DateTime? get ultimaMudanca => _ultimaMudanca;
  DateTime? get ultimaSyncCompleta => _ultimaSyncCompleta;

  /// 🔥 NOVO: Verificação real de internet via HTTP (funciona no Windows)
  Future<bool> _verificarInternetReal() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> inicializar() async {
    await _carregarUltimaSyncCompleta();
    
    // 🔥 No Windows, connectivity_plus não é fiável — usar HTTP direto
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _isOnline = await _verificarInternetReal();
      print('🌐 [Windows] Conectividade via DNS: ${_isOnline ? "ONLINE ✅" : "OFFLINE ❌"}');
    } else {
      final result = await _connectivity.checkConnectivity();
      _isOnline = !result.contains(ConnectivityResult.none);
      print('🌐 Conectividade inicial: ${_isOnline ? "ONLINE ✅" : "OFFLINE ❌"}');
    }

    _ultimaMudanca = DateTime.now();

    if (_ultimaSyncCompleta != null) {
      final minutos = DateTime.now().difference(_ultimaSyncCompleta!).inMinutes;
      print('📊 Última sync completa: há $minutos minutos');
    } else {
      print('📊 Nenhuma sync completa registrada');
    }

    // 🔥 No Windows: polling periódico em vez de stream (mais fiável)
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _iniciarPollingWindows();
    } else {
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _handleConnectivityChange,
      );
    }
  }

  /// 🔥 NOVO: Polling para Windows (verifica a cada 15s)
  Timer? _pollingTimer;
  void _iniciarPollingWindows() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final novoEstado = await _verificarInternetReal();
      if (novoEstado != _isOnline) {
        print('🔄 [Windows] Mudança detectada via polling: ${novoEstado ? "ONLINE ✅" : "OFFLINE ❌"}');
        _aplicarMudanca(novoEstado);
      }
    });
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final novoEstado = !results.contains(ConnectivityResult.none);
    
    if (novoEstado != _isOnline) {
      print('🔄 Mudança detectada: ${novoEstado ? "ONLINE ✅" : "OFFLINE ❌"}');
      _debounceTimer?.cancel();

      if (!novoEstado) {
        _debounceTimer = Timer(_debounceDelay, () => _aplicarMudanca(novoEstado));
      } else {
        _aplicarMudanca(novoEstado);
      }
    }
  }

  void _aplicarMudanca(bool novoEstado) {
    final estadoAnterior = _isOnline;
    _isOnline = novoEstado;
    _ultimaMudanca = DateTime.now();
    
    if (_isOnline) _modoOfflineManual = false;
    
    print('✅ Estado atualizado: ${_isOnline ? "ONLINE" : "OFFLINE"}');
    
    bool forcarSyncCompleto = false;
    if (novoEstado && !estadoAnterior) {
      final agora = DateTime.now();
      if (_ultimaSyncCompleta == null) {
        forcarSyncCompleto = true;
        print('🔄 Primeira sync - forçando sincronização completa');
      } else {
        final minutosSemSync = agora.difference(_ultimaSyncCompleta!).inMinutes;
        forcarSyncCompleto = minutosSemSync > 30;
        if (forcarSyncCompleto) {
          print('🔄 Passou $minutosSemSync min sem sync - forçando sincronização');
        } else {
          print('✅ Última sync há $minutosSemSync min - dados ainda válidos');
        }
      }
    }
    
    for (var listener in _listeners) {
      try {
        listener(_isOnline, forcarSyncCompleto);
      } catch (e) {
        print('⚠️ Erro ao notificar listener: $e');
      }
    }
  }

  void addListener(Function(bool isOnline, bool forcarSync) callback) {
    _listeners.add(callback);
  }

  void removeListener(Function(bool, bool) callback) {
    _listeners.remove(callback);
  }

  void activarModoOfflineManual() {
    _modoOfflineManual = true;
    print('📴 Modo offline manual ATIVADO');
  }

  Future<void> marcarSyncCompleta() async {
    _ultimaSyncCompleta = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ultima_sync_completa', _ultimaSyncCompleta!.toIso8601String());
    print('✅ Sync completa registrada: ${_ultimaSyncCompleta}');
  }

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

Future<bool> verificarConectividade() async {
  bool online;

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    online = await _verificarInternetReal();
  } else {
    final result = await _connectivity.checkConnectivity();
    online = !result.contains(ConnectivityResult.none);
  }

  if (online != _isOnline) _aplicarMudanca(online);
  return online;
}

  Future<void> limparHistoricoSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ultima_sync_completa');
    _ultimaSyncCompleta = null;
    print('🗑️ Histórico de sync limpo');
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _debounceTimer?.cancel();
    _pollingTimer?.cancel(); // 🔥 Cancelar polling também
    _listeners.clear();
    print('🔌 ConectividadeService encerrado');
  }
}