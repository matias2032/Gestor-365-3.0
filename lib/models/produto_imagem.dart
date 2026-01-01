// lib/models/produto_imagem.dart

class ProdutoImagemFields {
  static const String idImagem = 'id_imagem';
  static const String idProduto = 'id_produto';
  static const String caminhoImagem = 'caminho_imagem';
  static const String legenda = 'legenda';
  static const String imagemPrincipal = 'imagem_principal';
}

class ProdutoImagem {
  final int? id; // id_imagem
  final int idProduto; // id_produto
  final String caminho; // caminho_imagem (local ou url)
  final String? legenda; // legenda
  final bool isPrincipal; // imagem_principal (convertido de INTEGER 1/0)

  ProdutoImagem({
    this.id,
    required this.idProduto,
    required this.caminho,
    this.legenda,
    this.isPrincipal = false,
  });

  // ✅ CORREÇÃO NO copyWith: Usa bool? para os parâmetros
  ProdutoImagem copyWith({
    int? id,
    int? idProduto,
    String? caminho,
    String? legenda,
    bool? isPrincipal, // <-- É BOOL
  }) {
    return ProdutoImagem(
      id: id ?? this.id,
      idProduto: idProduto ?? this.idProduto,
      caminho: caminho ?? this.caminho,
      legenda: legenda ?? this.legenda,
      isPrincipal: isPrincipal ?? this.isPrincipal,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      ProdutoImagemFields.idImagem: id,
      ProdutoImagemFields.idProduto: idProduto,
      ProdutoImagemFields.caminhoImagem: caminho,
      ProdutoImagemFields.legenda: legenda,
      // OK: Converte bool para int (1 ou 0) para o Banco de Dados
      ProdutoImagemFields.imagemPrincipal: isPrincipal ? 1 : 0,
    };
  }

  factory ProdutoImagem.fromMap(Map<String, dynamic> map) {
    return ProdutoImagem(
      id: map[ProdutoImagemFields.idImagem] as int?,
      idProduto: map[ProdutoImagemFields.idProduto] as int,
      caminho: map[ProdutoImagemFields.caminhoImagem] as String,
      legenda: map[ProdutoImagemFields.legenda] as String?,
      // OK: Converte int (1/0) para bool para o modelo Dart
      isPrincipal: (map[ProdutoImagemFields.imagemPrincipal] as int?) == 1,
    );
  }
}