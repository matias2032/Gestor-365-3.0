// lib/services/conectividade_service.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';


class ConectividadeService {
  static final ConectividadeService instance = ConectividadeService._internal();
  ConectividadeService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  // Estado
  bool _isOnline = true;
  bool _modoOfflineManual = false;
  DateTime? _ultimaMudanca;
  DateTime? _ultimaSyncCompleta; // 🔥 NOVO
  
  // Callbacks
  final List<Function(bool, bool)> _listeners = []; // 🔥 MODIFICADO: recebe flag de forçarSync
  
  // Debounce
  Timer? _debounceTimer;
  static const Duration _debounceDelay = Duration(seconds: 5);

  // Getters
  bool get isOnline => _isOnline;
  bool get modoOfflineManual => _modoOfflineManual;
  DateTime? get ultimaMudanca => _ultimaMudanca;
  DateTime? get ultimaSyncCompleta => _ultimaSyncCompleta; // 🔥 NOVO

  /// Inicializar serviço
  Future<void> inicializar() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);
    _ultimaMudanca = DateTime.now();
    
    print('🌐 Conectividade inicial: ${_isOnline ? "ONLINE" : "OFFLINE"}');
    
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
    );
  }

  /// Handle mudança de conectividade COM DEBOUNCE
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final novoEstado = !results.contains(ConnectivityResult.none);
    
    if (novoEstado != _isOnline) {
      print('🔄 Mudança detectada: ${novoEstado ? "ONLINE" : "OFFLINE"}');
      
      _debounceTimer?.cancel();
      
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
    
    if (_isOnline) {
      _modoOfflineManual = false;
    }
    
    print('✅ Estado atualizado: ${_isOnline ? "ONLINE" : "OFFLINE"}');
    
    // 🔥 NOVO: Decidir se deve forçar sync completo
    bool forcarSyncCompleto = false;
    
    if (novoEstado && !estadoAnterior) {
      // Voltou online após estar offline
      final agora = DateTime.now();
      
      if (_ultimaSyncCompleta == null) {
        forcarSyncCompleto = true; // Primeira vez
      } else {
        final minutosSemSync = agora.difference(_ultimaSyncCompleta!).inMinutes;
        forcarSyncCompleto = minutosSemSync > 30; // Só sincronizar se passou 30+ min
      }
    }
    
    // Notificar listeners COM FLAG
    for (var listener in _listeners) {
      listener(_isOnline, forcarSyncCompleto);
    }
  }

  /// Adicionar listener (agora recebe 2 parâmetros)
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
    print('📴 Modo offline manual ACTIVADO');
  }

  /// Marcar que foi feita uma sync completa
  void marcarSyncCompleta() {
    _ultimaSyncCompleta = DateTime.now();
    print('✅ Sync completa registada: ${_ultimaSyncCompleta}');
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

  /// Dispose
  void dispose() {
    _connectivitySubscription?.cancel();
    _debounceTimer?.cancel();
    _listeners.clear();
  }
}