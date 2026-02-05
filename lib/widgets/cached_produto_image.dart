// lib/widgets/cached_produto_image.dart

import 'package:flutter/material.dart';
import 'dart:io';
import '../services/supabase_storage_service.dart';

class CachedProdutoImage extends StatefulWidget {
  final String? imagePath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedProdutoImage({
    super.key,
    required this.imagePath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<CachedProdutoImage> createState() => _CachedProdutoImageState();
}

class _CachedProdutoImageState extends State<CachedProdutoImage> {
  final _storageService = SupabaseStorageService.instance;
  String? _localPath;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedProdutoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _loadImage();
    }
  }

  // 🔥 SUBSTITUIR o método _loadImage completo

Future<void> _loadImage() async {
  if (widget.imagePath == null || widget.imagePath!.isEmpty) {
    setState(() {
      _isLoading = false;
      _hasError = true;
    });
    return;
  }

  setState(() {
    _isLoading = true;
    _hasError = false;
  });

  try {
    // 🔥 CASO 1: URL do Supabase - baixar e cachear
    if (_storageService.isSupabaseUrl(widget.imagePath!)) {
      // ✅ CORRETO
final cachedPath = await _storageService.cacheImagemLocal(widget.imagePath!);

      if (mounted) {
        setState(() {
          _localPath = cachedPath;
          _isLoading = false;
          _hasError = cachedPath == null;
        });
      }
    } 
    // 🔥 CASO 2: Caminho local - verificar se existe
    else {
      final file = File(widget.imagePath!);
      final exists = await file.exists();
      
      if (mounted) {
        setState(() {
          _localPath = exists ? widget.imagePath : null;
          _isLoading = false;
          _hasError = !exists;
        });
      }
      
      // 🔥 DEBUG: Avisar se não existe
      if (!exists) {
        print('⚠️ Imagem local não encontrada: ${widget.imagePath}');
      }
    }
  } catch (e) {
    print('❌ Erro ao carregar imagem: $e');
    if (mounted) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }
}

  @override
  Widget build(BuildContext context) {
    // Placeholder durante carregamento
    if (_isLoading) {
      return widget.placeholder ?? 
        Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey.shade200,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
    }

    // Erro ou sem imagem
    if (_hasError || _localPath == null) {
      return widget.errorWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey.shade300,
          child: Icon(
            Icons.broken_image,
            size: 48,
            color: Colors.grey.shade500,
          ),
        );
    }

    // Exibir imagem
    return Image.file(
      File(_localPath!),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        return widget.errorWidget ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey.shade300,
            child: Icon(
              Icons.broken_image,
              size: 48,
              color: Colors.grey.shade500,
            ),
          );
      },
    );
  }
}