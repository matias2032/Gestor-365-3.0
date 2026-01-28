// lib/screens/editar_usuario.dart

import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../services/base_de_dados.dart';
import '../services/sessao_service.dart';
import '../services/servico_logs.dart';
import '../services/supabase_sync_service.dart';

class EditarUsuarioScreen extends StatefulWidget {
  const EditarUsuarioScreen({super.key});

  @override
  State<EditarUsuarioScreen> createState() => _EditarUsuarioScreenState();
}

class _EditarUsuarioScreenState extends State<EditarUsuarioScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _apelidoController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();
    final SupabaseSyncService _syncService = SupabaseSyncService.instance;
  
  Usuario? _usuarioAtual;
  bool _isLoading = true;
  bool _isModoEdicao = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _carregarDadosUsuario();
  }

  Future<void> _carregarDadosUsuario() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final usuario = SessaoService.instance.usuarioAtual;
      
      if (usuario != null) {
        // Buscar dados atualizados do banco
        final usuarioAtualizado = await DatabaseService.instance.readUsuario(usuario.id!);
        
        if (usuarioAtualizado != null) {
          setState(() {
            _usuarioAtual = usuarioAtualizado;
            _nomeController.text = usuarioAtualizado.nome;
            _apelidoController.text = usuarioAtualizado.apelido;
            _emailController.text = usuarioAtualizado.email;
            _telefoneController.text = usuarioAtualizado.telefone ?? '';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _salvarAlteracoes() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Criar usuário atualizado mantendo os dados que não podem ser editados
      final usuarioAtualizado = _usuarioAtual!.copyWith(
        id: _usuarioAtual!.id,
      );

      // Atualizar apenas email e telefone no banco
      final Map<String, dynamic> dadosAtualizados = {
        'id_usuario': _usuarioAtual!.id,
        'nome': _usuarioAtual!.nome,
        'apelido': _usuarioAtual!.apelido,
        'email': _emailController.text.trim(),
        'senha_hash': _usuarioAtual!.senhaHash,
        'telefone': _telefoneController.text.trim().isNotEmpty 
            ? _telefoneController.text.trim() 
            : null,
        'data_cadastro': _usuarioAtual!.dataCadastro,
        'idprovincia': _usuarioAtual!.idProvincia,
        'idcidade': _usuarioAtual!.idCidade,
        'idperfil': _usuarioAtual!.idPerfil,
        'primeira_senha': _usuarioAtual!.primeiraSenha,
        'ativo': _usuarioAtual!.ativo,
      };

      final usuarioParaAtualizar = Usuario.fromMap(dadosAtualizados);
      await DatabaseService.instance.updateUsuario(usuarioParaAtualizar);

      // 🔥 NOVO: Sincronizar edição
await SupabaseSyncService.instance.updateUsuario(usuarioParaAtualizar);
await SupabaseSyncService.instance.forcarSincronizacaoCompleta();
      
// 🔥 ADICIONAR LOG
await ServicoLogs.instance.registrarEdicaoUsuario(
  '${usuarioAtualizado.nome} ${usuarioAtualizado.apelido}',
);

      if (mounted) {
        // Mostrar mensagem de sucesso
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dados atualizados com sucesso! Você será deslogado.'),
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
            '/',
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar dados: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _apelidoController.dispose();
    _emailController.dispose();
    _telefoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Dados'),
        backgroundColor: Colors.deepOrange,
        elevation: 0,
        // ✅ REMOVIDO: Botão de editar no AppBar
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Header com avatar
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    padding: const EdgeInsets.only(bottom: 30),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.deepOrange.shade100,
                            child: Text(
                              _usuarioAtual?.nome.substring(0, 1).toUpperCase() ?? 'U',
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${_usuarioAtual?.nome ?? ''} ${_usuarioAtual?.apelido ?? ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _getPerfilNome(_usuarioAtual?.idPerfil),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
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
                          // Card de informações básicas
                          _buildInfoCard(
                            title: 'Informações Básicas',
                            icon: Icons.person_outline,
                            children: [
                              _buildReadOnlyField(
                                label: 'Nome',
                                value: _usuarioAtual?.nome ?? '',
                                icon: Icons.person,
                              ),
                              const SizedBox(height: 16),
                              _buildReadOnlyField(
                                label: 'Apelido',
                                value: _usuarioAtual?.apelido ?? '',
                                icon: Icons.badge,
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Card de contato (editável)
                          _buildInfoCard(
                            title: 'Informações de Contato',
                            icon: Icons.contact_phone,
                            children: [
                              TextFormField(
                                controller: _emailController,
                                enabled: _isModoEdicao,
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: const Icon(Icons.email),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: _isModoEdicao 
                                      ? Colors.white 
                                      : Colors.grey[100],
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor, insira o email.';
                                  }
                                  if (!value.contains('@')) {
                                    return 'Insira um email válido.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _telefoneController,
                                enabled: _isModoEdicao,
                                decoration: InputDecoration(
                                  labelText: 'Telefone',
                                  prefixIcon: const Icon(Icons.phone),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: _isModoEdicao 
                                      ? Colors.white 
                                      : Colors.grey[100],
                                ),
                                keyboardType: TextInputType.phone,
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Card de conta
                          _buildInfoCard(
                            title: 'Informações da Conta',
                            icon: Icons.info_outline,
                            children: [
                              _buildReadOnlyField(
                                label: 'Data de Cadastro',
                                value: _formatarData(_usuarioAtual?.dataCadastro ?? ''),
                                icon: Icons.calendar_today,
                              ),
                              const SizedBox(height: 16),
                              _buildReadOnlyField(
                                label: 'Status',
                                value: _usuarioAtual?.ativo == 1 ? 'Ativo' : 'Inativo',
                                icon: Icons.check_circle,
                                valueColor: _usuarioAtual?.ativo == 1 
                                    ? Colors.green 
                                    : Colors.red,
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 30),
                          
                          // ✅ NOVA LÓGICA DE BOTÕES
                          if (_isModoEdicao) ...[
                            // MODO EDIÇÃO: Botões Cancelar e Salvar
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isSaving ? null : () {
                                      setState(() {
                                        _isModoEdicao = false;
                                        // Restaurar valores originais
                                        _emailController.text = _usuarioAtual!.email;
                                        _telefoneController.text = _usuarioAtual!.telefone ?? '';
                                      });
                                    },
                                    icon: const Icon(Icons.close, color: Colors.grey),
                                    label: const Text(
                                      'Cancelar',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      side: const BorderSide(color: Colors.grey),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isSaving ? null : _salvarAlteracoes,
                                    icon: _isSaving
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.save, color: Colors.white),
                                    label: Text(
                                      _isSaving ? 'Salvando...' : 'Salvar Alterações',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      backgroundColor: Colors.deepOrange,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            // MODO VISUALIZAÇÃO: Botão Grande "Editar Meus Dados"
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.deepOrange,
                                    Colors.deepOrange.shade700,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.deepOrange.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isModoEdicao = true;
                                  });
                                },
                                icon: const Icon(Icons.edit, color: Colors.white, size: 24),
                                label: const Text(
                                  'Editar Meus Dados',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.deepOrange, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              color: valueColor ?? Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _getPerfilNome(int? idPerfil) {
    switch (idPerfil) {
      case 1:
        return 'Administrador';
      case 2:
        return 'Gerente';
      case 3:
        return 'Funcionário';
      case 4:
        return 'Cliente';
      default:
        return 'Usuário';
    }
  }

  String _formatarData(String dataIso) {
    try {
      final data = DateTime.parse(dataIso);
      return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
    } catch (e) {
      return dataIso;
    }
  }
}