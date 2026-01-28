// lib/screens/primeira_troca_senha.dart

import 'package:flutter/material.dart';
import 'package:bcrypt/bcrypt.dart';
import '../services/base_de_dados.dart';
import '../services/sessao_service.dart';
import '../services/servico_autenticacao.dart';
import '../models/usuario.dart';


class PrimeiraTrocaSenhaScreen extends StatefulWidget {
  const PrimeiraTrocaSenhaScreen({super.key});

  @override
  State<PrimeiraTrocaSenhaScreen> createState() => _PrimeiraTrocaSenhaScreenState();
}

class _PrimeiraTrocaSenhaScreenState extends State<PrimeiraTrocaSenhaScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _novaSenhaController = TextEditingController();
  final TextEditingController _confirmarSenhaController = TextEditingController();

  bool _obscureNovaSenha = true;
  bool _obscureConfirmarSenha = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _novaSenhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  Future<void> _trocarSenha() async {
  if (!_formKey.currentState!.validate()) {
    return;
  }

  setState(() {
    _isLoading = true;
  });

  try {
    final usuario = SessaoService.instance.usuarioAtual;
    if (usuario == null) {
      throw Exception('Usuário não encontrado na sessão');
    }

    print('🔄 Iniciando troca de senha para usuário ID: ${usuario.id}');

    // 🔥 USAR O NOVO MÉTODO DO SERVIÇO DE AUTENTICAÇÃO
    final sucesso = await ServicoAutenticacao()
        .trocarPrimeiraSenha(usuario.id!, _novaSenhaController.text);

    if (!sucesso) {
      throw Exception('Falha ao atualizar senha no banco de dados');
    }

    print('✅ Senha trocada com sucesso!');

    if (mounted) {
      // Exibe mensagem de sucesso
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Senha alterada com sucesso! Por favor, faça login novamente.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // Aguarda 2 segundos
      await Future.delayed(const Duration(seconds: 2));

      // Limpa sessão e redireciona para login
      SessaoService.instance.limparSessao();
      
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  } catch (e, stackTrace) {
    print('❌ Erro ao trocar senha: $e');
    print('📍 StackTrace: $stackTrace');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao trocar senha: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final usuario = SessaoService.instance.usuarioAtual;

    return WillPopScope(
      // 🔥 Impede voltar - usuário DEVE trocar a senha
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ícone de segurança
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.security,
                          size: 60,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Título
                      const Text(
                        'Troca de Senha Obrigatória',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      // Mensagem de boas-vindas
                      Text(
                        'Olá, ${usuario?.nome ?? 'usuário'}!',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Instrução
                      Text(
                        'Por segurança, você precisa criar uma nova senha antes de continuar.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

                      // Campo Nova Senha
                      TextFormField(
                        controller: _novaSenhaController,
                        obscureText: _obscureNovaSenha,
                        decoration: InputDecoration(
                          labelText: 'Nova Senha *',
                          hintText: 'Mínimo 8 caracteres',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureNovaSenha
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureNovaSenha = !_obscureNovaSenha;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Digite a nova senha';
                          }
                          if (value.length < 8) {
                            return 'A senha deve ter no mínimo 8 caracteres';
                          }
                          if (value == '12345678') {
                            return 'Não use a senha padrão. Crie uma nova senha.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Campo Confirmar Senha
                      TextFormField(
                        controller: _confirmarSenhaController,
                        obscureText: _obscureConfirmarSenha,
                        decoration: InputDecoration(
                          labelText: 'Confirmar Nova Senha *',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmarSenha
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmarSenha = !_obscureConfirmarSenha;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Confirme a nova senha';
                          }
                          if (value != _novaSenhaController.text) {
                            return 'As senhas não coincidem';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 30),

                      // Requisitos de senha
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Requisitos da senha:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text('• Mínimo 8 caracteres', style: TextStyle(fontSize: 12)),
                            Text('• Diferente da senha padrão (12345678)', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Botão Alterar Senha
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _trocarSenha,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Alterar Senha',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}