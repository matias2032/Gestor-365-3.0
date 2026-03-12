// lib/screens/configuracoes_impressora_screen.dart

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/impressora_service.dart';
import '../widgets/app_sidebar.dart';

class ConfiguracoesImpressoraScreen extends StatefulWidget {
  const ConfiguracoesImpressoraScreen({super.key});

  @override
  State<ConfiguracoesImpressoraScreen> createState() =>
      _ConfiguracoesImpressoraScreenState();
}

class _ConfiguracoesImpressoraScreenState
    extends State<ConfiguracoesImpressoraScreen> {
  final _impressoraService = ImpressoraService.instance;

  List<Printer> _impressoras = [];
  String? _nomeSelecionado;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final impressoras = await _impressoraService.listarImpressoras();
    final nomeSalvo = await _impressoraService.lerImpressoraPadrao();
    setState(() {
      _impressoras = impressoras;
      _nomeSelecionado = nomeSalvo;
      _carregando = false;
    });
  }

  Future<void> _salvar(String name) async {
    await _impressoraService.salvarImpressoraPadrao(name);
    setState(() => _nomeSelecionado = name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Impressora "$name" definida como padrão'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _remover() async {
    await _impressoraService.removerImpressoraPadrao();
    setState(() => _nomeSelecionado = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impressora padrão removida')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impressora Padrão'),
        backgroundColor: Colors.teal,
        actions: [
          if (_nomeSelecionado != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remover impressora padrão',
              onPressed: _remover,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar lista',
            onPressed: _carregar,
          ),
        ],
      ),
        drawer: const AppSidebar(currentRoute: '/configuracoes_impressora'),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Banner de estado atual ──────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: _nomeSelecionado != null
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  child: Row(
                    children: [
                      Icon(
                        _nomeSelecionado != null
                            ? Icons.check_circle
                            : Icons.warning_amber_rounded,
                        color: _nomeSelecionado != null
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _nomeSelecionado != null
                              ? 'Impressora padrão: $_nomeSelecionado'
                              : 'Nenhuma impressora padrão definida.\nSelecione uma abaixo.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _nomeSelecionado != null
                                ? Colors.green.shade800
                                : Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    'Impressoras disponíveis',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),

                // ── Lista de impressoras ────────────────────
                if (_impressoras.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Nenhuma impressora encontrada.\nVerifique se a impressora está ligada e conectada.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: _impressoras.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16),
                      itemBuilder: (_, i) {
                        final impressora = _impressoras[i];
                        final isSelecionada =
                            impressora.name == _nomeSelecionado;
                        return ListTile(
                          leading: Icon(
                            Icons.print,
                            color: isSelecionada ? Colors.teal : Colors.grey,
                          ),
                          title: Text(
                            impressora.name,
                            style: TextStyle(
                              fontWeight: isSelecionada
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: isSelecionada
                              ? const Icon(Icons.check_circle,
                                  color: Colors.teal)
                              : const Icon(Icons.radio_button_unchecked,
                                  color: Colors.grey),
                          onTap: () => _salvar(impressora.name),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}