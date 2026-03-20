import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum StatusLicenca { valida, expirada, bloqueada, erroRelogio }

class LicencaService {
  static final LicencaService instance = LicencaService._();
  LicencaService._();

  final _storage = const FlutterSecureStorage();
  final int diasDeTolerancia = 4; // Quanto tempo ele pode ficar sem internet

  // Chaves do storage
  static const _keyExpiracao = 'licenca_validade';
  static const _keyUltimoUso = 'licenca_ultimo_acesso';

  /// Verifica o estado atual da licença localmente (funciona offline)
  Future<StatusLicenca> verificarStatusLicenca() async {
    final agora = DateTime.now();
    
    final expStr = await _storage.read(key: _keyExpiracao);
    final ultStr = await _storage.read(key: _keyUltimoUso);

    if (expStr == null) return StatusLicenca.expirada; // Nunca sincronizou

    final dataExpiracao = DateTime.parse(expStr);
    
    // 🛡️ Anti-Time Travel: Verifica se o relógio foi atrasado
    if (ultStr != null) {
      final dataUltimoUso = DateTime.parse(ultStr);
      if (agora.isBefore(dataUltimoUso.subtract(const Duration(minutes: 5)))) {
        return StatusLicenca.erroRelogio;
      }
    }

    // 🛡️ Verifica se a licença venceu
    if (agora.isAfter(dataExpiracao)) {
      return StatusLicenca.expirada;
    }

    // Atualiza o "último acesso" para a próxima verificação de relógio
    await _storage.write(key: _keyUltimoUso, value: agora.toIso8601String());
    return StatusLicenca.valida;
  }

  /// Atualiza a licença via Supabase (exige internet)
  Future<void> atualizarLicencaServidor() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final data = await Supabase.instance.client
          .from('usuario')
          .select('ativo')
          .eq('id_usuario', user.id) // Ajuste para sua lógica de ID
          .single();

      if (data['ativo'] == 1) {
        // Se ativo, renova o prazo offline por mais X dias
        final novaValidade = DateTime.now().add(Duration(days: diasDeTolerancia));
        await _storage.write(key: _keyExpiracao, value: novaValidade.toIso8601String());
      } else {
        // Se inativo no server, mata a licença local imediatamente
        await _storage.write(key: _keyExpiracao, value: DateTime.now().subtract(const Duration(days: 1)).toIso8601String());
      }
    } catch (e) {
      print('⚠️ Não foi possível atualizar licença com o servidor: $e');
    }
  }
}