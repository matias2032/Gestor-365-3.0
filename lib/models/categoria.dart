// lib/models/categoria.dart


import '../models/produto.dart'; 

class CategoriaFields {
  static final List<String> values = [
    idCategoria, nomeCategoria, descricao
  ];
  
  static const String idCategoria = 'id_categoria';
  static const String nomeCategoria = 'nome_categoria';
  static const String descricao = 'descricao';
}

class Categoria {
  final int? id; // id_categoria
  final String nome; // nome_categoria
  final String? descricao; // descricao
  
  // Lista de produtos associados
  final List<Produto>? produtosAssociados; // 💡 AGORA USA O MODELO PRODUTO COMPLETO

  Categoria({
    this.id,
    required this.nome,
    this.descricao,
    this.produtosAssociados, // Opcional ao criar/atualizar
  });

  // Converte Objeto Dart para Map (Para DB)
  Map<String, dynamic> toMap() {
    return {
      CategoriaFields.idCategoria: id,
      CategoriaFields.nomeCategoria: nome,
      CategoriaFields.descricao: descricao,
    };
  }

  // Cria Objeto Dart a partir de Map (Do DB)
  factory Categoria.fromMap(Map<String, dynamic> map) {
    return Categoria(
      id: map[CategoriaFields.idCategoria] as int?,
      nome: map[CategoriaFields.nomeCategoria] as String,
      descricao: map[CategoriaFields.descricao] as String?,
    );
  }

  // 💡 MÉTODO copyWith ADICIONADO (CORREÇÃO DO ERRO DE SINTAXE)
  Categoria copyWith({
    int? id,
    String? nome,
    String? descricao,
    List<Produto>? produtosAssociados,
  }) {
    return Categoria(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      produtosAssociados: produtosAssociados ?? this.produtosAssociados,
    );
  }
}