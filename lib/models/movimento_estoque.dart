// lib/models/movimento_estoque.dart

class MovimentoEstoqueFields {
  static const String idMovimento = 'id_movimento';
  static const String idProduto = 'id_produto';
  static const String idUsuario = 'id_usuario';
  static const String tipoMovimento = 'tipo_movimento';
  static const String quantidade = 'quantidade';
  static const String quantidadeAnterior = 'quantidade_anterior';
  static const String quantidadeNova = 'quantidade_nova';
  static const String motivo = 'motivo';
  static const String dataMovimento = 'data_movimento';
}

enum TipoMovimento {
  acrescimo,
  reducao;

  String get valor => name.toUpperCase();

  static TipoMovimento fromString(String valor) {
    return valor.toUpperCase() == 'ACRESCIMO' 
        ? TipoMovimento.acrescimo 
        : TipoMovimento.reducao;
  }
}

class MovimentoEstoque {
  final int? id;
  final int idProduto;
  final int idUsuario;
  final TipoMovimento tipoMovimento;
  final int quantidade;
  final int quantidadeAnterior;
  final int quantidadeNova;
  final String? motivo;
  final String dataMovimento;
  
  // Campos auxiliares para exibição
  final String? nomeProduto;
  final String? nomeUsuario;

  MovimentoEstoque({
    this.id,
    required this.idProduto,
    required this.idUsuario,
    required this.tipoMovimento,
    required this.quantidade,
    required this.quantidadeAnterior,
    required this.quantidadeNova,
    this.motivo,
    required this.dataMovimento,
    this.nomeProduto,
    this.nomeUsuario,
  });

  Map<String, dynamic> toMap() {
    return {
      MovimentoEstoqueFields.idMovimento: id,
      MovimentoEstoqueFields.idProduto: idProduto,
      MovimentoEstoqueFields.idUsuario: idUsuario,
      MovimentoEstoqueFields.tipoMovimento: tipoMovimento.valor,
      MovimentoEstoqueFields.quantidade: quantidade,
      MovimentoEstoqueFields.quantidadeAnterior: quantidadeAnterior,
      MovimentoEstoqueFields.quantidadeNova: quantidadeNova,
      MovimentoEstoqueFields.motivo: motivo,
      MovimentoEstoqueFields.dataMovimento: dataMovimento,
    };
  }

  factory MovimentoEstoque.fromMap(Map<String, dynamic> map) {
    return MovimentoEstoque(
      id: map[MovimentoEstoqueFields.idMovimento] as int?,
      idProduto: map[MovimentoEstoqueFields.idProduto] as int,
      idUsuario: map[MovimentoEstoqueFields.idUsuario] as int,
      tipoMovimento: TipoMovimento.fromString(
        map[MovimentoEstoqueFields.tipoMovimento] as String
      ),
      quantidade: map[MovimentoEstoqueFields.quantidade] as int,
      quantidadeAnterior: map[MovimentoEstoqueFields.quantidadeAnterior] as int,
      quantidadeNova: map[MovimentoEstoqueFields.quantidadeNova] as int,
      motivo: map[MovimentoEstoqueFields.motivo] as String?,
      dataMovimento: map[MovimentoEstoqueFields.dataMovimento] as String,
      nomeProduto: map['nome_produto'] as String?,
      nomeUsuario: map['nome_usuario'] as String?,
    );
  }

  String get descricaoMovimento {
    final acao = tipoMovimento == TipoMovimento.acrescimo 
        ? 'Acréscimo' 
        : 'Redução';
    return '$acao de $quantidade unidades';
  }

  String get descricaoCompleta {
    final produto = nomeProduto ?? 'Produto #$idProduto';
    final usuario = nomeUsuario ?? 'Usuário #$idUsuario';
    final data = DateTime.parse(dataMovimento).toLocal();
    
    return '$descricaoMovimento de $produto por $usuario em ${_formatarData(data)}';
  }

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/'
           '${data.month.toString().padLeft(2, '0')}/'
           '${data.year} às ${data.hour.toString().padLeft(2, '0')}:'
           '${data.minute.toString().padLeft(2, '0')}';
  }
}