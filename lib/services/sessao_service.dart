// lib/services/sessao_service.dart

import '../models/usuario.dart';

class SessaoService {
  static final SessaoService instance = SessaoService._init();
  SessaoService._init();

  Usuario? _usuarioAtual;

  Usuario? get usuarioAtual => _usuarioAtual;

  void setUsuario(Usuario usuario) {
    _usuarioAtual = usuario;
  }

  void limparSessao() {
    _usuarioAtual = null;
  }

  bool get isLogado => _usuarioAtual != null;
}