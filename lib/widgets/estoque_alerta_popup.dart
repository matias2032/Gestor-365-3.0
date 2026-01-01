
// ==========================================
// 2. WIDGET POPUP - lib/widgets/estoque_alerta_popup.dart
// ==========================================

import 'package:flutter/material.dart';
import '../services/estoque_alerta_service.dart';

class EstoqueAlertaPopup extends StatelessWidget {
  const EstoqueAlertaPopup({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EstoqueAlertaService.instance,
      builder: (context, _) {
        final service = EstoqueAlertaService.instance;
        
        if (!service.alertaVisivel || !service.temAlertas) {
          return const SizedBox.shrink();
        }

        return Positioned(
          top: 80,
          left: 16,
          right: 16,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: service.corAlerta,
                  width: 3,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: service.corAlerta,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          service.nivelMaisCritico == NivelAlerta.vermelho
                              ? 'Estoque Crítico!'
                              : 'Alerta de Estoque',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: service.corAlerta,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => service.marcarComoLido(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${service.totalAlertas} produto(s) com estoque baixo:',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: service.alertas.length > 5 ? 5 : service.alertas.length,
                      itemBuilder: (context, index) {
                        final alerta = service.alertas[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: alerta.nivel == NivelAlerta.vermelho
                                      ? Colors.red
                                      : Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  alerta.nome,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Text(
                                '${alerta.quantidade} un.',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: alerta.nivel == NivelAlerta.vermelho
                                      ? Colors.red
                                      : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (service.alertas.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+ ${service.alertas.length - 5} outros produtos...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => service.marcarComoLido(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: service.corAlerta),
                          ),
                          child: Text(
                            'Marcar como Lido',
                            style: TextStyle(color: service.corAlerta),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            service.marcarComoLido();
                            Navigator.pushNamed(context, '/gerenciar_produtos');
                          },
                          icon: const Icon(Icons.inventory),
                          label: const Text('Repor'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: service.corAlerta,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
      