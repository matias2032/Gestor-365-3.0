// lib/services/servico_autenticacao.dart

import 'package:bcrypt/bcrypt.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/resultado_autenticacao.dart';
import '../models/usuario.dart';
import 'base_de_dados.dart';

class ServicoAutenticacao {
  final DatabaseService _dbService = DatabaseService.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<ResultadoAutenticacao> login(String credencial, String password) async {
    try {
      print('🔐 Tentando login com: $credencial');
      
      // 1. 🔥 Buscar SOMENTE LOCALMENTE (o Supabase já sincronizou no app init)
      final Usuario? user = await _dbService.readUsuarioByCredencial(credencial);

      if (user == null) {
        print('❌ Usuário não encontrado: $credencial');
        return ResultadoAutenticacao(
          status: StatusAutenticacao.usuarioNaoEncontrado,
          mensagem: 'Credencial ou senha incorretos.',
        );
      }

      print('✅ Usuário encontrado: ${user.nome} (ID: ${user.id})');
      print('🔑 Hash armazenado: ${user.senhaHash.substring(0, 20)}...');

      // 2. Verificar se o usuário está ativo
      if (user.ativo == 0) {
        print('⚠️ Usuário inativo');
        return ResultadoAutenticacao(
          status: StatusAutenticacao.credenciaisInvalidas,
          mensagem: 'Sua conta está inativa. Contacte o administrador.',
        );
      }

      // 3. 🔥 VERIFICAR PRIMEIRA SENHA ANTES de validar senha
      if (user.primeiraSenha == 1) {
        print('⚠️ Primeira senha detectada - precisa trocar');
        
        // 🔥 Validar se a senha é a senha padrão (12345678)
   final bool senhaValidaPrimeira = BCrypt.checkpw(password, user.senhaHash);

        if (!senhaValidaPrimeira) {
          print('❌ Senha padrão incorreta');
          return ResultadoAutenticacao(
            status: StatusAutenticacao.credenciaisInvalidas,
            mensagem: 'Credencial ou senha incorretos.',
          );
        }

        return ResultadoAutenticacao(
          status: StatusAutenticacao.primeiraSenha,
          mensagem: 'Você precisa definir uma nova senha.',
          usuario: user,
        );
      }

      // 4. Verificar senha normal
      print('🔓 Validando senha...');
    final bool senhaValida = BCrypt.checkpw(password, user.senhaHash);

      if (!senhaValida) {
        print('❌ Senha incorreta');
        return ResultadoAutenticacao(
          status: StatusAutenticacao.credenciaisInvalidas,
          mensagem: 'Credencial ou senha incorretos.',
        );
      }

      print('✅ Login bem-sucedido!');
      return ResultadoAutenticacao(
        status: StatusAutenticacao.sucesso,
        usuario: user,
        mensagem: 'Login realizado com sucesso!',
      );
    } catch (e, stackTrace) {
      print('❌ Erro durante autenticação: $e');
      print('📍 StackTrace: $stackTrace');
      return ResultadoAutenticacao(
        status: StatusAutenticacao.erroDesconhecido,
        mensagem: 'Erro interno: ${e.toString()}',
      );
    }
  }

  // 🔥 ADICIONAR: Método para trocar a primeira senha
  Future<bool> trocarPrimeiraSenha(int idUsuario, String novaSenha) async {
    try {
      print('🔄 Trocando primeira senha para usuário ID: $idUsuario');
      
      // 1. Gerar novo hash
    final novoHash = BCrypt.hashpw(novaSenha, BCrypt.gensalt());
      
      print('🔑 Novo hash gerado: ${novoHash.substring(0, 20)}...');

      // 2. 🔥 Atualizar NO SUPABASE PRIMEIRO
      try {
        await _supabase
            .from('usuario')
            .update({
              'senha_hash': novoHash,
              'primeira_senha': 0,
            })
            .eq('id_usuario', idUsuario);
        
        print('✅ Senha atualizada no Supabase');
      } catch (e) {
        print('⚠️ Erro ao atualizar no Supabase: $e');
      }

      // 3. Atualizar LOCALMENTE
      final db = await _dbService.database;
      final result = await db.update(
        'usuario',
        {
          'senha_hash': novoHash,
          'primeira_senha': 0,
        },
        where: 'id_usuario = ?',
        whereArgs: [idUsuario],
      );

      print('✅ Senha atualizada localmente (rows: $result)');

      return result > 0;
    } catch (e, stackTrace) {
      print('❌ Erro ao trocar senha: $e');
      print('📍 StackTrace: $stackTrace');
      return false;
    }
  }
}