// lib/screens/detalhes_usuario.dart

import 'package:flutter/material.dart';
import 'package:bcrypt/bcrypt.dart';import '../models/usuario.dart';
import '../services/base_de_dados.dart';
import '../services/supabase_sync_service.dart';

class DetalhesUsuarioScreen extends StatefulWidget {
  final int usuarioId;
  const DetalhesUsuarioScreen({required this.usuarioId, super.key});

  @override
  State<DetalhesUsuarioScreen> createState() => _DetalhesUsuarioScreenState();
}

class _DetalhesUsuarioScreenState extends State<DetalhesUsuarioScreen> {
  late Future<Usuario?> _usuarioFuture;
  final DatabaseService _dbService = DatabaseService.instance;
    final SupabaseSyncService _syncService = SupabaseSyncService.instance;

  @override
  void initState() {
    super.initState();
    _loadUsuario();
  }

  void _loadUsuario() {
    setState(() {
      _usuarioFuture = _dbService.readUsuario(widget.usuarioId);
    });
  }

  // Lógica para Desligar/Afastar
  Future<void> _toggleAfastamento(Usuario usuario) async {
    final bool isAtivo = usuario.ativo == 1;
    final String acao = isAtivo ? 'Afastar' : 'Reativar';
    final String status = isAtivo ? 'Inativo' : 'Ativo';

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$acao Funcionário'),
        content: Text('Tem certeza que deseja $acao ${usuario.nome}? O status dele mudará para "$status".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isAtivo ? Colors.red : Colors.green,
            ),
            child: Text(acao),
          ),
        ],
      ),
    );

    if (shouldProceed == true) {
      await _dbService.toggleAtivoUsuario(usuario.id!, !isAtivo);
      await _syncService.toggleAtivoUsuario(usuario.id!, !isAtivo);

      _loadUsuario();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${usuario.nome} foi marcado como $status.')),
        );
      }
    }
  }

  // 🔥 NOVA FUNÇÃO: Reiniciar Senha
  // Método _reiniciarSenha COMPLETO E CORRIGIDO:

Future<void> _reiniciarSenha(Usuario usuario) async {
  final shouldProceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_reset, color: Colors.orange),
          SizedBox(width: 10),
          Text('Reiniciar Senha'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tem certeza que deseja reiniciar a senha de ${usuario.nome}?',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⚠️ Atenção:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                SizedBox(height: 8),
                Text('• A senha será redefinida para: 12345678'),
                Text('• O usuário será obrigado a criar uma nova senha no próximo login'),
                Text('• Esta ação não pode ser desfeita'),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: const Text('Reiniciar Senha'),
        ),
      ],
    ),
  );

  if (shouldProceed != true) return;

  // Mostrar loading
  if (mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  try {
  const senhaPadrao = '12345678';
final senhaHash = BCrypt.hashpw(senhaPadrao, BCrypt.gensalt());

    final usuarioAtualizado = usuario.copyWith(
      senhaHash: senhaHash,
      primeiraSenha: 1,
    );

    // 🔥 updateUsuario JÁ sincroniza com Supabase automaticamente
    await _syncService.updateUsuario(usuarioAtualizado);
    


    if (mounted) {
      Navigator.of(context).pop(); // Fechar loading
    }

    _loadUsuario();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Senha de ${usuario.nome} reiniciada e sincronizada!\n'
            'Nova senha: 12345678',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      Navigator.of(context).pop(); // Fechar loading
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao reiniciar senha: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  // Função para formatar o nome do perfil
  String _getPerfilName(int? idPerfil) {
    switch (idPerfil) {
      case 1: return 'Administrador';
      case 2: return 'Gerente';
      case 3: return 'Funcionário';
      default: return 'Cliente';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do Usuário'),
        backgroundColor: Colors.deepOrange,
      ),
      body: FutureBuilder<Usuario?>(
        future: _usuarioFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Erro ao carregar os dados do usuário.'));
          }

          final usuario = snapshot.data!;
          final isAtivo = usuario.ativo == 1;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. DADOS PESSOAIS
                Card(
                  elevation: 4,
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(usuario.nome[0], style: const TextStyle(fontSize: 24)),
                    ),
                    title: Text(
                      '${usuario.nome} ${usuario.apelido}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(_getPerfilName(usuario.idPerfil)),
                    trailing: Icon(
                      isAtivo ? Icons.check_circle : Icons.person_off,
                      color: isAtivo ? Colors.green : Colors.red,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. DETALHES DE CONTATO
                const Text(
                  'Detalhes de Contato:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ListTile(
                  leading: const Icon(Icons.email),
                  title: Text(usuario.email),
                ),
                ListTile(
                  leading: const Icon(Icons.phone),
                  title: Text(usuario.telefone ?? 'Não fornecido'),
                ),
                
                // 3. AÇÕES DE GERENCIAMENTO
                const Divider(),
                const Text(
                  'Ações de Gerenciamento:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                // 🔥 NOVO: Botão Reiniciar Senha
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _reiniciarSenha(usuario),
                    icon: const Icon(Icons.lock_reset, color: Colors.white),
                    label: const Text(
                      'REINICIAR SENHA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Botão Afastar/Reativar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _toggleAfastamento(usuario),
                    icon: Icon(
                      isAtivo ? Icons.person_off : Icons.person_add,
                      color: Colors.white,
                    ),
                    label: Text(
                      isAtivo ? 'AFASTAR / DESLIGAR FUNCIONÁRIO' : 'REATIVAR FUNCIONÁRIO',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAtivo ? Colors.red.shade700 : Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Informação sobre reinício de senha
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ao reiniciar a senha, o usuário receberá a senha padrão (12345678) e '
                          'será obrigado a criar uma nova senha no próximo login.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}