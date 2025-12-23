// lib/models/resultado_autenticacao.dart (Novo nome)

import 'usuario.dart';

enum StatusAutenticacao {
  sucesso,
  credenciaisInvalidas, // Substitui invalidCredentials
  usuarioNaoEncontrado, // Substitui userNotFound
  erroDesconhecido, 
  primeiraSenha,    // Substitui unknownError
}

class ResultadoAutenticacao {
  final StatusAutenticacao status;
  final Usuario? usuario;
  final String? mensagem;

  ResultadoAutenticacao({required this.status, this.usuario, this.mensagem});
}