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
  
  // Callbacks
  final List<Function(bool)> _listeners = [];
  
  // Debounce
  Timer? _debounceTimer;
  static const Duration _debounceDelay = Duration(seconds: 5);

  // Getters
  bool get isOnline => _isOnline;
  bool get modoOfflineManual => _modoOfflineManual;
  DateTime? get ultimaMudanca => _ultimaMudanca;

  /// Inicializar serviço
  Future<void> inicializar() async {
    // Verificar estado inicial
    final result = await _connectivity.checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);
    _ultimaMudanca = DateTime.now();
    
    print('🌐 Conectividade inicial: ${_isOnline ? "ONLINE" : "OFFLINE"}');
    
    // Listener de mudanças
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
    );
  }

  /// Handle mudança de conectividade COM DEBOUNCE
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final novoEstado = !results.contains(ConnectivityResult.none);
    
    // Se mudou de estado
    if (novoEstado != _isOnline) {
      print('🔄 Mudança detectada: ${novoEstado ? "ONLINE" : "OFFLINE"}');
      
      // Cancelar timer anterior
      _debounceTimer?.cancel();
      
      // Se ficou OFFLINE → aplicar debounce
      if (!novoEstado) {
        _debounceTimer = Timer(_debounceDelay, () {
          _aplicarMudanca(novoEstado);
        });
      } 
      // Se voltou ONLINE → aplicar imediatamente
      else {
        _aplicarMudanca(novoEstado);
      }
    }
  }

  /// Aplicar mudança de estado
  void _aplicarMudanca(bool novoEstado) {
    _isOnline = novoEstado;
    _ultimaMudanca = DateTime.now();
    
    // Se voltou online, resetar modo offline manual
    if (_isOnline) {
      _modoOfflineManual = false;
    }
    
    print('✅ Estado atualizado: ${_isOnline ? "ONLINE" : "OFFLINE"}');
    
    // Notificar listeners
    for (var listener in _listeners) {
      listener(_isOnline);
    }
  }

  /// Adicionar listener
  void addListener(Function(bool) callback) {
    _listeners.add(callback);
  }

  /// Remover listener
  void removeListener(Function(bool) callback) {
    _listeners.remove(callback);
  }

  /// Activar modo offline manual (utilizador escolheu continuar offline)
  void activarModoOfflineManual() {
    _modoOfflineManual = true;
    print('📴 Modo offline manual ACTIVADO');
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