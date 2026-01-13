// lib/screens/tela_login.dart (VERSÃO COM REDIRECIONAMENTO PARA PRIMEIRA SENHA)

import 'package:flutter/material.dart';
import '../services/servico_autenticacao.dart';
import '../services/sessao_service.dart';
import '../models/resultado_autenticacao.dart';
import '../services/servico_logs.dart';
import '../services/pedido_contador_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _credencialController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final ServicoAutenticacao _authService = ServicoAutenticacao();

  bool _isLoading = false;
  String _errorMessage = '';
  bool _obscurePassword = true;

  @override
  void dispose() {
    _credencialController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  
Future<void> _handleLogin() async {
  setState(() {
    _isLoading = true;
    _errorMessage = '';
  });

  final credencial = _credencialController.text.trim();
  final password = _passwordController.text;

  if (credencial.isEmpty || password.isEmpty) {
    setState(() {
      _errorMessage = 'Por favor, preencha todos os campos.';
      _isLoading = false;
    });
    return;
  }

  try {
    final result = await _authService.login(credencial, password);

    // 🔥 CASO 1: Primeira senha - redireciona para troca obrigatória
    if (result.status == StatusAutenticacao.primeiraSenha && result.usuario != null) {
      // ✅ CORREÇÃO: Adicionar await
      await SessaoService.instance.setUsuario(result.usuario!);
      
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/primeira_troca_senha');
      }
      return;
    }

    // 🔥 CASO 2: Login bem-sucedido
    if (result.status == StatusAutenticacao.sucesso && result.usuario != null) {
      // ✅ CORREÇÃO: Adicionar await
      await SessaoService.instance.setUsuario(result.usuario!);
      
      // Carrega contador de pedidos
      await PedidoContadorService.instance.carregarContador(result.usuario!.id!);
      
      // Registra log de login
      await ServicoLogs.instance.registrarLogin(
        result.usuario!.id!,
        '${result.usuario!.nome} ${result.usuario!.apelido}',
      );
      
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/dashboard');
      }
    } 
    // 🔥 CASO 3: Falha ou erro
    else {
      setState(() {
        _errorMessage = result.mensagem ?? 'Erro desconhecido.';
        _isLoading = false;
      });
    }
  } catch (e) {
    setState(() {
      _errorMessage = 'Erro ao conectar: $e';
      _isLoading = false;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Logo ou Ícone
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.restaurant_menu,
                      size: 60,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Título
                  const Text(
                    'Bar Digital POS',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Acesso ao Sistema',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Campo Credencial
                  TextField(
                    controller: _credencialController,
                    decoration: InputDecoration(
                      labelText: 'E-mail, Telefone ou Apelido',
                      hintText: 'Digite suas credenciais',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 20),

                  // Campo Senha
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      hintText: 'Digite sua senha',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onSubmitted: (_) => _handleLogin(),
                  ),
                  const SizedBox(height: 30),

                  // Mensagem de erro
                  if (_errorMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Botão Entrar
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
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
                              'Entrar',
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
    );
  }
}