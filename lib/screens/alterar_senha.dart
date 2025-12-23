// lib/screens/alterar_senha.dart

import 'package:flutter/material.dart';
import 'package:flutter_bcrypt/flutter_bcrypt.dart';
import '../services/base_de_dados.dart';
import '../services/sessao_service.dart';
import '../models/usuario.dart';
import '../services/servico_logs.dart';

class AlterarSenhaScreen extends StatefulWidget {
  const AlterarSenhaScreen({super.key});

  @override
  State<AlterarSenhaScreen> createState() => _AlterarSenhaScreenState();
}

class _AlterarSenhaScreenState extends State<AlterarSenhaScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _senhaAtualController = TextEditingController();
  final TextEditingController _novaSenhaController = TextEditingController();
  final TextEditingController _confirmacaoSenhaController = TextEditingController();
  
  bool _obscureSenhaAtual = true;
  bool _obscureNovaSenha = true;
  bool _obscureConfirmacao = true;
  bool _isLoading = false;
  
  String? _errorMessage;

  @override
  void dispose() {
    _senhaAtualController.dispose();
    _novaSenhaController.dispose();
    _confirmacaoSenhaController.dispose();
    super.dispose();
  }

  Future<void> _alterarSenha() async {
    // Limpar mensagem de erro anterior
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final usuario = SessaoService.instance.usuarioAtual;
      
      if (usuario == null) {
        throw Exception('Usuário não encontrado na sessão.');
      }

      final senhaAtual = _senhaAtualController.text;
      final novaSenha = _novaSenhaController.text;
      final confirmacaoSenha = _confirmacaoSenhaController.text;

      // 1. Verificar se a senha atual está correta
      final senhaAtualCorreta = await FlutterBcrypt.verify(
        password: senhaAtual,
        hash: usuario.senhaHash,
      );

      if (!senhaAtualCorreta) {
        setState(() {
          _errorMessage = 'Senha atual incorreta.';
          _isLoading = false;
        });
        return;
      }

      // 2. Verificar se nova senha e confirmação coincidem
      if (novaSenha != confirmacaoSenha) {
        setState(() {
          _errorMessage = 'A nova senha e a confirmação não coincidem.';
          _isLoading = false;
        });
        return;
      }

      // 3. Verificar se a nova senha não foi usada anteriormente
      final senhasAnteriores = await _buscarHistoricoSenhas(usuario.id!);
      
      for (final senhaAnteriorHash in senhasAnteriores) {
        final senhaJaUsada = await FlutterBcrypt.verify(
          password: novaSenha,
          hash: senhaAnteriorHash,
        );
        
        if (senhaJaUsada) {
          setState(() {
            _errorMessage = 'Esta senha já foi utilizada anteriormente. Escolha uma senha diferente.';
            _isLoading = false;
          });
          return;
        }
      }

      // 4. Gerar hash da nova senha
      final novaSenhaHash = await FlutterBcrypt.hashPw(
        password: novaSenha,
        salt: await FlutterBcrypt.salt(),
      );

      // 5. Salvar senha antiga no histórico
      await _salvarSenhaNoHistorico(usuario.id!, usuario.senhaHash);

      // 6. Atualizar senha no banco
      final usuarioAtualizado = usuario.copyWith(
        senhaHash: novaSenhaHash,
        primeiraSenha: 0, // Marca que não é mais a primeira senha
      );

      await DatabaseService.instance.updateUsuario(usuarioAtualizado);

      // 🔥 ADICIONAR LOG
await ServicoLogs.instance.registrarAlteracaoSenha(
  '${usuario.nome} ${usuario.apelido}',
);

      if (mounted) {
        // Mostrar mensagem de sucesso
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Senha alterada com sucesso! Você será deslogado.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Aguardar 2 segundos e deslogar
        await Future.delayed(const Duration(seconds: 2));
        
        if (mounted) {
          // Limpar sessão
          SessaoService.instance.limparSessao();
          
          // Navegar para login
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao alterar senha: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<List<String>> _buscarHistoricoSenhas(int idUsuario) async {
    try {
      final db = await DatabaseService.instance.database;
      
      final result = await db.query(
        'historico_senhas',
        columns: ['senha_hash'],
        where: 'id_usuario = ?',
        whereArgs: [idUsuario],
        orderBy: 'data_alteracao DESC',
        limit: 5, // Últimas 5 senhas
      );

      return result.map((row) => row['senha_hash'] as String).toList();
    } catch (e) {
      print('Erro ao buscar histórico de senhas: $e');
      return [];
    }
  }

  Future<void> _salvarSenhaNoHistorico(int idUsuario, String senhaHash) async {
    try {
      final db = await DatabaseService.instance.database;
      
      await db.insert('historico_senhas', {
        'id_usuario': idUsuario,
        'senha_hash': senhaHash,
        'data_alteracao': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Erro ao salvar senha no histórico: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alterar Senha'),
        backgroundColor: Colors.deepOrange,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header decorativo
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.deepOrange,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              padding: const EdgeInsets.only(bottom: 40, top: 20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_reset,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Segurança da Conta',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mantenha sua senha sempre segura',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            // Formulário
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Card de informações
                    Card(
                      elevation: 0,
                      color: Colors.blue.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Para sua segurança, você não poderá usar senhas anteriormente utilizadas.',
                                style: TextStyle(
                                  color: Colors.blue.shade900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Mensagem de erro
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Campo: Senha Atual
                    Text(
                      'Senha Atual',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _senhaAtualController,
                      obscureText: _obscureSenhaAtual,
                      decoration: InputDecoration(
                        hintText: 'Digite sua senha atual',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureSenhaAtual
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureSenhaAtual = !_obscureSenhaAtual;
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
                          return 'Por favor, insira a senha atual.';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Divider
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey[300])),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Nova Senha',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey[300])),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Campo: Nova Senha
                    Text(
                      'Nova Senha',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _novaSenhaController,
                      obscureText: _obscureNovaSenha,
                      decoration: InputDecoration(
                        hintText: 'Digite a nova senha',
                        prefixIcon: const Icon(Icons.lock),
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
                          return 'Por favor, insira a nova senha.';
                        }
                        if (value.length < 6) {
                          return 'A senha deve ter pelo menos 6 caracteres.';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Campo: Confirmação
                    Text(
                      'Confirmar Nova Senha',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmacaoSenhaController,
                      obscureText: _obscureConfirmacao,
                      decoration: InputDecoration(
                        hintText: 'Confirme a nova senha',
                        prefixIcon: const Icon(Icons.lock_clock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmacao
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmacao = !_obscureConfirmacao;
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
                          return 'Por favor, confirme a nova senha.';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Requisitos de senha
                    Card(
                      elevation: 0,
                      color: Colors.grey[50],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Requisitos da Senha:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildRequirement('Mínimo de 6 caracteres'),
                            _buildRequirement('Diferente de senhas anteriores'),
                            _buildRequirement('Nova senha e confirmação devem ser iguais'),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Botão Alterar Senha
                    ElevatedButton(
                      onPressed: _isLoading ? null : _alterarSenha,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.deepOrange,
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
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'ALTERAR SENHA',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Botão Cancelar
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.of(context).pop();
                            },
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirement(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}