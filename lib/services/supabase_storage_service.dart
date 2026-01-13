// lib/services/supabase_storage_service.dart
// SUBSTITUIR O ARQUIVO COMPLETO

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;

class SupabaseStorageService {
  static final SupabaseStorageService instance = SupabaseStorageService._init();
  SupabaseStorageService._init();

  final SupabaseClient _supabase = Supabase.instance.client;
  
  static const String _bucketName = 'produtos-imagens';

  /// Faz upload de uma imagem e retorna a URL pública
  Future<String?> uploadImagem(String localPath) async {
    try {
      final file = File(localPath);
      
      if (!await file.exists()) {
        print('❌ Arquivo não encontrado: $localPath');
        return null;
      }

      // Gerar nome único
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(localPath);
      final fileName = 'produto_$timestamp$extension';
      
      print('📤 Iniciando upload: $fileName');

      // 🔥 CORREÇÃO 1: Usar uploadBinary ao invés de upload
      final bytes = await file.readAsBytes();
      
      await _supabase.storage
          .from(_bucketName)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: _getContentType(extension),
              upsert: false, // Não sobrescrever
            ),
          );

      // Obter URL pública
      final publicUrl = _supabase.storage
          .from(_bucketName)
          .getPublicUrl(fileName);

      print('✅ Upload concluído: $publicUrl');
      return publicUrl;
      
    } on StorageException catch (e) {
      // 🔥 TRATAMENTO ESPECÍFICO DE ERROS
      if (e.statusCode == '403' || e.message.contains('policy')) {
        print('❌ Erro 403: Verifique as políticas RLS do bucket no Supabase');
        print('   Execute o SQL de correção de políticas!');
      } else if (e.statusCode == '409') {
        print('⚠️ Arquivo já existe, tentando com novo nome...');
        // Tentar novamente com timestamp diferente
        await Future.delayed(const Duration(milliseconds: 100));
        return uploadImagem(localPath);
      } else {
        print('❌ StorageException: ${e.message} (${e.statusCode})');
      }
      return null;
    } catch (e) {
      print('❌ Erro inesperado ao fazer upload: $e');
      return null;
    }
  }

  /// Retorna o Content-Type baseado na extensão
  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  /// Faz upload de múltiplas imagens
  Future<List<String>> uploadMultiplasImagens(List<String> localPaths) async {
    final urls = <String>[];
    
    for (final localPath in localPaths) {
      final url = await uploadImagem(localPath);
      if (url != null) {
        urls.add(url);
      } else {
        print('⚠️ Falha no upload de: $localPath');
      }
    }
    
    return urls;
  }

  /// Deleta uma imagem do Storage
  Future<bool> deleteImagem(String publicUrl) async {
    try {
      final uri = Uri.parse(publicUrl);
      final fileName = uri.pathSegments.last;
      
      await _supabase.storage
          .from(_bucketName)
          .remove([fileName]);
      
      print('✅ Imagem deletada: $fileName');
      return true;
      
    } catch (e) {
      print('❌ Erro ao deletar imagem: $e');
      return false;
    }
  }

  /// Verifica se um caminho é uma URL do Supabase
  bool isSupabaseUrl(String caminho) {
    return caminho.startsWith('http') && 
           caminho.contains('supabase');
  }

  /// 🔥 NOVO: Verifica se o bucket existe e está configurado
  Future<bool> verificarConfiguracao() async {
    try {
      // Tentar listar arquivos (verifica permissões)
      await _supabase.storage
          .from(_bucketName)
          .list(
            path: '',
            searchOptions: const SearchOptions(limit: 1),
          );
      
      print('✅ Bucket configurado corretamente');
      return true;
      
    } catch (e) {
      print('❌ Erro de configuração do bucket: $e');
      print('   Verifique se o bucket "$_bucketName" existe e está público');
      return false;
    }
  }

  /// Baixa uma imagem do Supabase para cache local
  Future<String?> cacheImagemLocal(String publicUrl) async {
    try {
      if (!isSupabaseUrl(publicUrl)) {
        return publicUrl; // Já é local
      }

      final fileName = Uri.parse(publicUrl).pathSegments.last;
      final cacheDir = Directory.systemTemp;
      final localPath = '${cacheDir.path}/$fileName';
      
      // Verificar se já existe em cache
      final cacheFile = File(localPath);
      if (await cacheFile.exists()) {
        return localPath;
      }

      // Baixar imagem
      final response = await _supabase.storage
          .from(_bucketName)
          .download(fileName);

      await cacheFile.writeAsBytes(response);
      return localPath;
      
    } catch (e) {
      print('❌ Erro ao cachear imagem: $e');
      return null;
    }
  }
}