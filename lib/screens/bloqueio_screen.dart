import 'package:flutter/material.dart';
import '../services/licenca_service.dart';

class BloqueioScreen extends StatelessWidget {
  final StatusLicenca motivo;
  const BloqueioScreen({super.key, required this.motivo});

  @override
  Widget build(BuildContext context) {
    String mensagem = "Acesso Suspenso";
    if (motivo == StatusLicenca.expirada) mensagem = "Necessário sincronizar com o servidor para continuar usando offline.";
    if (motivo == StatusLicenca.erroRelogio) mensagem = "Alteração de data detectada. Ajuste o relógio para o modo automático.";

    return PopScope(
      canPop: false, // Bloqueia botão voltar do Android
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_person, size: 100, color: Colors.red),
                const SizedBox(height: 24),
                Text(mensagem, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/splash'),
                  child: const Text("Tentar Novamente (Ligue o Wi-Fi)"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}