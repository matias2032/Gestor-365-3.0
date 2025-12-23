// lib/services/servico_autenticacao.dart

import 'package:flutter_bcrypt/flutter_bcrypt.dart';
import '../models/resultado_autenticacao.dart';
import '../models/usuario.dart';
import 'base_de_dados.dart';


class ServicoAutenticacao {
  final DatabaseService _dbService = DatabaseService.instance;

  Future<ResultadoAutenticacao> login(String credencial, String password) async {
    try {
      // 1. Buscar usuário pela credencial (email, telefone ou apelido)
      final Usuario? user =
          await _dbService.readUsuarioByCredencial(credencial);

      if (user == null) {
        return ResultadoAutenticacao(
          status: StatusAutenticacao.usuarioNaoEncontrado,
          mensagem: 'Credencial ou senha incorretos.',
        );
      }

      // 2. Verificar se o usuário está ativo
      if (user.ativo == 0) {
        return ResultadoAutenticacao(
          status: StatusAutenticacao.credenciaisInvalidas,
          mensagem: 'Sua conta está inativa. Contacte o administrador.',
        );
      }

      // 3. Verificar senha com BCrypt
      final bool senhaValida = await FlutterBcrypt.verify(
        password: password,
        hash: user.senhaHash,
      );

      if (!senhaValida) {
        return ResultadoAutenticacao(
          status: StatusAutenticacao.credenciaisInvalidas,
          mensagem: 'Credencial ou senha incorretos.',
        );
      }

      // 4. 🔥 NOVO: Verificar se é a primeira senha
      if (user.primeiraSenha == 1) {
        return ResultadoAutenticacao(
          status: StatusAutenticacao.primeiraSenha,
          mensagem: 'Você precisa definir uma nova senha.',
          usuario: user,
        );
      }

      // 5. Login bem-sucedido
      return ResultadoAutenticacao(
        status: StatusAutenticacao.sucesso,
        usuario: user,
        mensagem: 'Login realizado com sucesso!',
      );
    } catch (e) {
      print('Erro durante autenticação: $e');
      return ResultadoAutenticacao(
        status: StatusAutenticacao.erroDesconhecido,
        mensagem: 'Erro interno de autenticação.',
      );
    }
  }
}
