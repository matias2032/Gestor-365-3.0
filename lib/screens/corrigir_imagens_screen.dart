// lib/screens/corrigir_imagens_screen.dart
// ADICIONAR IMPORT NO TOPO:

import 'package:flutter/material.dart';
import '../services/supabase_sync_service.dart';
import '../services/supabase_storage_service.dart'; // 🔥 NOVO

class CorrigirImagensScreen extends StatefulWidget {
  const CorrigirImagensScreen({super.key});

  @override
  State<CorrigirImagensScreen> createState() => _CorrigirImagensScreenState();
}

class _CorrigirImagensScreenState extends State<CorrigirImagensScreen> {
  final _syncService = SupabaseSyncService.instance;
  
  bool _isProcessing = false;
  String _status = 'Pronto para iniciar';
  final List<String> _logs = [];

  Future<void> _executarCorrecao() async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
      _status = 'Processando...';
      _logs.clear();
      _logs.add('⏳ Iniciando correção de imagens...');
    });

    try {
      // Verificar conectividade
      if (!_syncService.isOnline) {
        throw Exception('Sem conexão com a internet');
      }
      
      _addLog('🌐 Conexão com Supabase: OK');
      
      // 🔥 NOVO: Verificar configuração do Storage
      _addLog('🔍 Verificando configuração do bucket...');
      
      final storageService = SupabaseStorageService.instance;
      final bucketOk = await storageService.verificarConfiguracao();
      
      if (!bucketOk) {
        throw Exception(
          'Bucket não configurado corretamente.\n'
          'Execute o SQL de correção de políticas no Supabase!'
        );
      }
      
      _addLog('✅ Bucket configurado corretamente');
      _addLog('📤 Fazendo upload de imagens locais...');
      
      // Executar correção
      await _syncService.corrigirImagensLocais();
      
      setState(() {
        _status = 'Concluído com sucesso!';
        _logs.add('✅ Todas as imagens foram corrigidas');
        _logs.add('');
        _logs.add('PRÓXIMOS PASSOS:');
        _logs.add('1. Feche e reabra o app');
        _logs.add('2. Verifique as imagens no Menu');
        _logs.add('3. Sincronize em outros dispositivos');
      });
      
      // Mostrar diálogo de sucesso
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 32),
                SizedBox(width: 12),
                Text('Sucesso!'),
              ],
            ),
            content: const Text(
              'Imagens corrigidas!\n\n'
              'Feche e reabra o app para ver as mudanças.'
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop(); // Voltar à tela anterior
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      
    } catch (e) {
      setState(() {
        _status = 'Erro durante processamento';
        _logs.add('❌ ERRO: $e');
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _addLog(String mensagem) {
    if (mounted) {
      setState(() {
        _logs.add(mensagem);
      });
    }
    print(mensagem);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Corrigir Imagens'),
        backgroundColor: Colors.deepOrange,
      ),
      body: Column(
        children: [
          // Card de status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isProcessing 
                  ? Colors.blue.shade50 
                  : (_status.contains('Concluído') 
                      ? Colors.green.shade50 
                      : Colors.grey.shade50),
              border: Border(
                bottom: BorderSide(
                  color: _isProcessing 
                      ? Colors.blue 
                      : (_status.contains('Concluído') 
                          ? Colors.green 
                          : Colors.grey.shade300),
                  width: 2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_isProcessing)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        _status.contains('Concluído') 
                            ? Icons.check_circle 
                            : Icons.info_outline,
                        color: _status.contains('Concluído') 
                            ? Colors.green 
                            : Colors.grey,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _status,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _isProcessing 
                              ? Colors.blue 
                              : (_status.contains('Concluído') 
                                  ? Colors.green 
                                  : Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Área de logs
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade50,
              child: _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_upload,
                            size: 80,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Pronto para corrigir imagens',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Este processo irá:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• Fazer upload de imagens locais\n'
                            '• Atualizar URLs no Supabase\n'
                            '• Sincronizar com outros dispositivos',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: log.startsWith('❌') 
                                  ? Colors.red 
                                  : (log.startsWith('✅') 
                                      ? Colors.green 
                                      : Colors.black87),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),

          // Botão de ação
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _executarCorrecao,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(
                _isProcessing 
                    ? 'Processando...' 
                    : 'Iniciar Correção',
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}