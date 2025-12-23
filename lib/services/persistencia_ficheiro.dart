import 'dart:io';
import 'package:path_provider/path_provider.dart';

// Função responsável por mover o ficheiro temporário para um local permanente
Future<String?> saveImagePermanently(String? tempPath) async {
  if (tempPath == null || tempPath.isEmpty) return null;

  try {
    final originalFile = File(tempPath);
    
    // Obter o diretório de documentos da aplicação
    final directory = await getApplicationDocumentsDirectory(); 
    
    // Criar um nome de ficheiro único
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg'; 
    final newPath = '${directory.path}/$fileName';
    
    // Copiar o ficheiro para o novo local permanente
    await originalFile.copy(newPath);
    
    // Retornar o caminho permanente para ser salvo no SQLite
    return newPath;
    
  } catch (e) {
    // É crucial lidar com exceções de IO
    print("Erro ao salvar a imagem permanentemente: $e");
    return null;
  }
}