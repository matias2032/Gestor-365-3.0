// lib/models/produto.dart (ATUALIZADO COM ESTOQUE)

import 'categoria.dart';
import 'produto_imagem.dart';

class ProdutoFields {
  static final List<String> values = [
    idProduto, nomeProduto, descricao, preco, precoPromocional, 
    ativo, dataCadastro, quantidadeEstoque
  ];
  
  static const String idProduto = 'id_produto';
  static const String nomeProduto = 'nome_produto';
  static const String descricao = 'descricao';
  static const String preco = 'preco';
  static const String precoPromocional = 'preco_promocional';
  static const String ativo = 'ativo';
  static const String dataCadastro = 'data_cadastro';

  static const String quantidadeEstoque = 'quantidade_estoque'; // 💡 NOVO
}

class Produto {
  final int? id; 
  final String nome;
  final String? descricao;
  final double preco;
  final double? precoPromocional;
  final int ativo;
  final String dataCadastro;
  // final int isDestaque;
  final int? quantidadeEstoque; // 💡 NOVO CAMPO
  
  final List<Categoria>? categoriasAssociadas; 
  final List<ProdutoImagem>? imagens; 

  Produto({
    this.id,
    required this.nome,
    this.descricao,
    required this.preco,
    this.precoPromocional,
    this.ativo = 1,
    required this.dataCadastro,
    // this.isDestaque = 0,
    this.quantidadeEstoque, // 💡 NOVO
    this.categoriasAssociadas,
    this.imagens, 
  });

  Map<String, dynamic> toMap() {
    return {
      ProdutoFields.idProduto: id,
      ProdutoFields.nomeProduto: nome,
      ProdutoFields.descricao: descricao,
      ProdutoFields.preco: preco,
      ProdutoFields.precoPromocional: precoPromocional,
      ProdutoFields.ativo: ativo,
      ProdutoFields.dataCadastro: dataCadastro,
           ProdutoFields.quantidadeEstoque: quantidadeEstoque, // 💡 NOVO
    };
  }

  factory Produto.fromMap(Map<String, dynamic> map) {
    return Produto(
      id: map[ProdutoFields.idProduto] as int?,
      nome: map[ProdutoFields.nomeProduto] as String,
      descricao: map[ProdutoFields.descricao] as String?,
      preco: (map[ProdutoFields.preco] as num).toDouble(), 
      precoPromocional: (map[ProdutoFields.precoPromocional] as num?)?.toDouble(),
      ativo: map[ProdutoFields.ativo] as int? ?? 1,
      dataCadastro: map[ProdutoFields.dataCadastro] as String? ?? '',
          quantidadeEstoque: map[ProdutoFields.quantidadeEstoque] as int?, // 💡 NOVO
    );
  }
  
  Produto copyWith({
    int? id,
    String? nome,
    String? descricao,
    double? preco,
    double? precoPromocional,
    int? ativo,
    String? dataCadastro,
    // int? isDestaque,
    int? quantidadeEstoque, // 💡 NOVO
    List<Categoria>? categoriasAssociadas,
    List<ProdutoImagem>? imagens,
  }) {
    return Produto(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      preco: preco ?? this.preco,
      precoPromocional: precoPromocional ?? this.precoPromocional,
      ativo: ativo ?? this.ativo,
      dataCadastro: dataCadastro ?? this.dataCadastro,
      // isDestaque: isDestaque ?? this.isDestaque,
      quantidadeEstoque: quantidadeEstoque ?? this.quantidadeEstoque, // 💡 NOVO
      categoriasAssociadas: categoriasAssociadas ?? this.categoriasAssociadas,
      imagens: imagens ?? this.imagens,
    );
  }
}