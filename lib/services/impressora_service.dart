// lib/services/impressora_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';

class ImpressoraService {
  static final ImpressoraService instance = ImpressoraService._internal();
  factory ImpressoraService() => instance;
  ImpressoraService._internal();

  static const _key = 'impressora_padrao';

  Future<void> salvarImpressoraPadrao(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, name);
  }

  Future<String?> lerImpressoraPadrao() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> removerImpressoraPadrao() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<Printer?> getImpressoraPadrao() async {
    final nomeSalvo = await lerImpressoraPadrao();
    if (nomeSalvo == null) return null;
    final todas = await Printing.listPrinters();
    try {
      return todas.firstWhere((p) => p.name == nomeSalvo);
    } catch (_) {
      // Impressora guardada já não está disponível
      return null;
    }
  }

  Future<List<Printer>> listarImpressoras() async {
    return Printing.listPrinters();
  }
}