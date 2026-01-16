// lib/widgets/conectividade_dialog.dart

import 'package:flutter/material.dart';
import '../services/conectividade_service.dart';

class ConectividadeDialog extends StatelessWidget {
  final VoidCallback? onReconectar;
  final VoidCallback? onContinuarOffline;
  final bool isPreSplash;

  const ConectividadeDialog({
    Key? key,
    this.onReconectar,
    this.onContinuarOffline,
    this.isPreSplash = false,
  }) : super(key: key);

  /// Mostrar dialog
  static Future<void> mostrar(
    BuildContext context, {
    VoidCallback? onReconectar,
    VoidCallback? onContinuarOffline,
    bool isPreSplash = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConectividadeDialog(
        onReconectar: onReconectar,
        onContinuarOffline: onContinuarOffline,
        isPreSplash: isPreSplash,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícone
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 40,
                color: Colors.orange,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Título
            const Text(
              'Sem Conexão',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Mensagem
            Text(
              isPreSplash
                  ? 'Não foi possível conectar à internet. Você pode tentar reconectar ou continuar em modo offline.'
                  : 'A conexão com a internet foi perdida. Você pode tentar reconectar ou continuar em modo offline.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Aviso de limitações
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.amber.shade200,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Modo offline possui funcionalidades limitadas',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Botões
            Column(
              children: [
                // Tentar Reconectar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      
                      // Verificar conectividade
                      final isOnline = await ConectividadeService.instance
                          .verificarConectividade();
                      
                      if (isOnline) {
                        // Callback de sucesso
                        onReconectar?.call();
                      } else {
                        // Mostrar novamente se ainda offline
                        if (context.mounted) {
                          await Future.delayed(const Duration(milliseconds: 300));
                          if (context.mounted) {
                            mostrar(
                              context,
                              onReconectar: onReconectar,
                              onContinuarOffline: onContinuarOffline,
                              isPreSplash: isPreSplash,
                            );
                          }
                        }
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar Reconectar'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 10),
                
                // Continuar Offline
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      
                      // Activar modo offline manual
                      ConectividadeService.instance.activarModoOfflineManual();
                      
                      // Callback
                      onContinuarOffline?.call();
                    },
                    icon: const Icon(Icons.airplanemode_active),
                    label: const Text('Continuar Offline'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}