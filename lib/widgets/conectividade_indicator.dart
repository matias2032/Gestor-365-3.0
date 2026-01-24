// lib/widgets/conectividade_indicator.dart

import 'package:flutter/material.dart';
import '../services/conectividade_service.dart';

class ConectividadeIndicator extends StatefulWidget {
  const ConectividadeIndicator({Key? key}) : super(key: key);

  @override
  State<ConectividadeIndicator> createState() => _ConectividadeIndicatorState();
}

class _ConectividadeIndicatorState extends State<ConectividadeIndicator> {
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _isOnline = ConectividadeService.instance.isOnline;
    
    // Listener
    ConectividadeService.instance.addListener(_onConnectivityChange);
  }

  @override
  void dispose() {
    ConectividadeService.instance.removeListener(_onConnectivityChange);
    super.dispose();
  }

  // 🔥 CORRIGIDO: Agora recebe 2 parâmetros (isOnline, forcarSync)
  void _onConnectivityChange(bool isOnline, bool forcarSync) {
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
      });
      
      // Opcional: você pode usar o forcarSync aqui se precisar
      if (forcarSync) {
        print('🔄 Sync completo será forçado');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _isOnline ? 'Conectado' : 'Sem conexão',
      child: GestureDetector(
        onTap: () => _mostrarDetalhes(context),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _isOnline 
                ? Colors.white.withOpacity(0.1) 
                : Colors.black.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isOnline ? Icons.wifi : Icons.wifi_off,
            color: _isOnline ? Colors.white : Colors.black,
            size: 20,
          ),
        ),
      ),
    );
  }

  void _mostrarDetalhes(BuildContext context) {
    final service = ConectividadeService.instance;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              service.isOnline ? Icons.check_circle : Icons.error,
              color: service.isOnline ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 10),
            Text(service.isOnline ? 'Online' : 'Offline'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              'Estado:',
              service.isOnline ? 'Conectado' : 'Sem conexão',
              service.isOnline ? Colors.green : Colors.red,
            ),
            if (service.modoOfflineManual) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                'Modo:',
                'Offline Manual',
                Colors.orange,
              ),
            ],
            if (service.ultimaMudanca != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                'Última mudança:',
                _formatarTempo(service.ultimaMudanca!),
                Colors.grey,
              ),
            ],
            // 🔥 NOVO: Mostrar última sync completa
            if (service.ultimaSyncCompleta != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                'Última sync:',
                _formatarTempo(service.ultimaSyncCompleta!),
                Colors.blue,
              ),
            ],
            if (!service.isOnline) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Colors.amber.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Funcionalidades limitadas no modo offline',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  String _formatarTempo(DateTime tempo) {
    final agora = DateTime.now();
    final diferenca = agora.difference(tempo);
    
    if (diferenca.inSeconds < 60) {
      return 'Agora mesmo';
    } else if (diferenca.inMinutes < 60) {
      return 'Há ${diferenca.inMinutes}m';
    } else if (diferenca.inHours < 24) {
      return 'Há ${diferenca.inHours}h';
    } else {
      return '${tempo.day}/${tempo.month} ${tempo.hour}:${tempo.minute.toString().padLeft(2, '0')}';
    }
  }
}