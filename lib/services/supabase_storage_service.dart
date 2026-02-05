// lib/services/supabase_storage_service.dart

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(localPath);
      final fileName = 'produto_$timestamp$extension';
      
      print('📤 Iniciando upload: $fileName');

      final bytes = await file.readAsBytes();
      
      await _supabase.storage
          .from(_bucketName)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: _getContentType(extension),
              upsert: false,
            ),
          );

      final publicUrl = _supabase.storage
          .from(_bucketName)
          .getPublicUrl(fileName);

      print('✅ Upload concluído: $publicUrl');
      return publicUrl;
      
    } on StorageException catch (e) {
      if (e.statusCode == '403' || e.message.contains('policy')) {
        print('❌ Erro 403: Verifique as políticas RLS do bucket no Supabase');
      } else if (e.statusCode == '409') {
        print('⚠️ Arquivo já existe, tentando com novo nome...');
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

  bool isSupabaseUrl(String caminho) {
    return caminho.startsWith('http') && 
           caminho.contains('supabase');
  }

  Future<bool> verificarConfiguracao() async {
    try {
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

  // 🔥 ÚNICO MÉTODO cacheImagemLocal (baixa e salva permanentemente)
  Future<String?> cacheImagemLocal(String publicUrl) async {
    try {
      if (!isSupabaseUrl(publicUrl)) {
        return publicUrl; // Já é local
      }

      final fileName = Uri.parse(publicUrl).pathSegments.last;
      
      // 🔥 DIRETÓRIO PERMANENTE
      final directory = await getApplicationDocumentsDirectory();
      final imagensDir = Directory('${directory.path}/produto_imagens');
      
      if (!await imagensDir.exists()) {
        await imagensDir.create(recursive: true);
      }
      
      final localPath = '${imagensDir.path}/$fileName';
      
      // Verificar se já existe
      final localFile = File(localPath);
      if (await localFile.exists()) {
        print('✅ Imagem já existe localmente: $localPath');
        return localPath;
      }

      // Baixar do Supabase
      print('📥 Baixando imagem: $fileName');
      final response = await _supabase.storage
          .from(_bucketName)
          .download(fileName);

      await localFile.writeAsBytes(response);
      print('✅ Imagem baixada e salva: $localPath');
      
      return localPath;
      
    } catch (e) {
      print('❌ Erro ao cachear/salvar imagem: $e');
      return null;
    }
  }
}