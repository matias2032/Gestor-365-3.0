// lib/widgets/estoque_badge.dart

import 'package:flutter/material.dart';
import '../services/estoque_alerta_service.dart';

/// Badge dinâmico para exibir no ícone de Estoque na Sidebar
/// - Sempre visível enquanto houver produtos < 20
/// - Cor: Laranja (< 20) ou Vermelho (< 10 ou = 0)
/// - Atualiza em tempo real quando há mudanças no estoque
class EstoqueBadge extends StatelessWidget {
  final Widget child;

  const EstoqueBadge({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EstoqueAlertaService.instance,
      builder: (context, _) {
        final service = EstoqueAlertaService.instance;
        
        // Não exibir badge se não houver alertas
        if (!service.temAlertas) {
          return child;
        }

        // Determinar cor do badge
        Color badgeColor;
        if (service.nivelMaisCritico == NivelAlerta.ruptura) {
          badgeColor = const Color(0xFF8B0000); // Vermelho escuro
        } else if (service.nivelMaisCritico == NivelAlerta.vermelho) {
          badgeColor = Colors.red;
        } else {
          badgeColor = Colors.orange;
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
                child: Center(
                  child: Text(
                    service.totalAlertas > 99 
                        ? '99+' 
                        : service.totalAlertas.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

