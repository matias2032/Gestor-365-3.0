import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

// 🔥 CORREÇÃO: Criar estrutura de pastas permanente
Future<String?> saveImagePermanently(String? tempPath) async {
  if (tempPath == null || tempPath.isEmpty) return null;

  try {
    final originalFile = File(tempPath);
    
    if (!await originalFile.exists()) {
      print("❌ Arquivo temporário não existe: $tempPath");
      return null;
    }
    
    // 🔥 CORREÇÃO: Usar diretório de aplicação persistente
    final directory = await getApplicationDocumentsDirectory();
    final imagensDir = Directory('${directory.path}/produto_imagens');
    
    // 🔥 GARANTIR que a pasta existe
    if (!await imagensDir.exists()) {
      await imagensDir.create(recursive: true);
    }
    
    // 🔥 MANTER extensão original
    final extension = path.extension(tempPath);
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}$extension';
    final newPath = '${imagensDir.path}/$fileName';
    
    // 🔥 COPIAR (não mover) para garantir persistência
    await originalFile.copy(newPath);
    
    print("✅ Imagem salva permanentemente: $newPath");
    return newPath;
    
  } catch (e) {
    print("❌ Erro ao salvar imagem permanentemente: $e");
    return null;
  }
}

// 🔥 NOVO: Verificar se caminho local existe
Future<bool> verificarImagemLocal(String localPath) async {
  try {
    final file = File(localPath);
    return await file.exists();
  } catch (e) {
    return false;
  }
}