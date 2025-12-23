// ========================================
// lib/models/pedido.dart - ATUALIZADO
// ========================================

import 'produto.dart';

class PedidoFields {
  static const String idPedido = 'id_pedido';
  static const String reference = 'reference';
  static const String idUsuario = 'id_usuario';
  static const String telefone = 'telefone';
  static const String email = 'email';
  static const String idTipoPagamento = 'idtipo_pagamento';
  // REMOVIDO: idTipoOrigemPedido e idTipoEntrega
  static const String dataPedido = 'data_pedido';
  static const String dataFimPedido = 'data_fim_pedido';
  static const String statusPedido = 'status_pedido';
  static const String notificacaoVista = 'notificacao_vista';
  static const String total = 'total';
  static const String enderecoJson = 'endereco_json';
  static const String valorPagoManual = 'valor_pago_manual';
  static const String dataFinalizacao = 'data_finalizacao';
  static const String bairro = 'bairro';
  static const String pontoReferencia = 'ponto_referencia';
  static const String troco = 'troco';
  static const String ocultoCliente = 'oculto_cliente';
}

class Pedido {
  final int? id;
  final String? reference;
  final int idUsuario;
  final String? telefone;
  final String? email;
  final int idTipoPagamento;
  // REMOVIDO: idTipoOrigemPedido e idTipoEntrega
  final String dataPedido;
  final String? dataFimPedido;
  final String statusPedido;
  final int notificacaoVista;
  final double total;
  final String? enderecoJson;
  final double? valorPagoManual;
  final String? dataFinalizacao;
  final String? bairro;
  final String? pontoReferencia;
  final double? troco;
  final int ocultoCliente;
  
  // Campos auxiliares (não salvos no BD diretamente)
  final List<ItemPedido>? itens;
  final String? nomeUsuario;
  
  Pedido({
    this.id,
    this.reference,
    required this.idUsuario,
    this.telefone,
    this.email,
    required this.idTipoPagamento,
    // REMOVIDO: idTipoOrigemPedido e idTipoEntrega com valores padrão
    required this.dataPedido,
    this.dataFimPedido,
    this.statusPedido = 'por finalizar',
    this.notificacaoVista = 0,
    required this.total,
    this.enderecoJson,
    this.valorPagoManual,
    this.dataFinalizacao,
    this.bairro,
    this.pontoReferencia,
    this.troco,
    this.ocultoCliente = 0,
    this.itens,
    this.nomeUsuario,
  });

  Map<String, dynamic> toMap() {
    return {
      PedidoFields.idPedido: id,
      PedidoFields.reference: reference,
      PedidoFields.idUsuario: idUsuario,
      PedidoFields.telefone: telefone,
      PedidoFields.email: email,
      PedidoFields.idTipoPagamento: idTipoPagamento,
      // REMOVIDO: idTipoOrigemPedido e idTipoEntrega
      PedidoFields.dataPedido: dataPedido,
      PedidoFields.dataFimPedido: dataFimPedido,
      PedidoFields.statusPedido: statusPedido,
      PedidoFields.notificacaoVista: notificacaoVista,
      PedidoFields.total: total,
      PedidoFields.enderecoJson: enderecoJson,
      PedidoFields.valorPagoManual: valorPagoManual,
      PedidoFields.dataFinalizacao: dataFinalizacao,
      PedidoFields.bairro: bairro,
      PedidoFields.pontoReferencia: pontoReferencia,
      PedidoFields.troco: troco,
      PedidoFields.ocultoCliente: ocultoCliente,
    };
  }

  factory Pedido.fromMap(Map<String, dynamic> map) {
    return Pedido(
      id: map[PedidoFields.idPedido] as int?,
      reference: map[PedidoFields.reference] as String?,
      idUsuario: map[PedidoFields.idUsuario] as int,
      telefone: map[PedidoFields.telefone] as String?,
      email: map[PedidoFields.email] as String?,
      idTipoPagamento: map[PedidoFields.idTipoPagamento] as int,
      // REMOVIDO: leitura de idTipoOrigemPedido e idTipoEntrega
      dataPedido: map[PedidoFields.dataPedido] as String,
      dataFimPedido: map[PedidoFields.dataFimPedido] as String?,
      statusPedido: map[PedidoFields.statusPedido] as String? ?? 'por finalizar',
      notificacaoVista: map[PedidoFields.notificacaoVista] as int? ?? 0,
      total: (map[PedidoFields.total] as num).toDouble(),
      enderecoJson: map[PedidoFields.enderecoJson] as String?,
      valorPagoManual: (map[PedidoFields.valorPagoManual] as num?)?.toDouble(),
      dataFinalizacao: map[PedidoFields.dataFinalizacao] as String?,
      bairro: map[PedidoFields.bairro] as String?,
      pontoReferencia: map[PedidoFields.pontoReferencia] as String?,
      troco: (map[PedidoFields.troco] as num?)?.toDouble(),
      ocultoCliente: map[PedidoFields.ocultoCliente] as int? ?? 0,
      nomeUsuario: map['nome_usuario'] as String?,
    );
  }

  Pedido copyWith({
    int? id,
    String? reference,
    int? idUsuario,
    String? telefone,
    String? email,
    int? idTipoPagamento,
    // REMOVIDO: parâmetros idTipoOrigemPedido e idTipoEntrega
    String? dataPedido,
    String? dataFimPedido,
    String? statusPedido,
    int? notificacaoVista,
    double? total,
    String? enderecoJson,
    double? valorPagoManual,
    String? dataFinalizacao,
    String? bairro,
    String? pontoReferencia,
    double? troco,
    int? ocultoCliente,
    List<ItemPedido>? itens,
    String? nomeUsuario,
  }) {
    return Pedido(
      id: id ?? this.id,
      reference: reference ?? this.reference,
      idUsuario: idUsuario ?? this.idUsuario,
      telefone: telefone ?? this.telefone,
      email: email ?? this.email,
      idTipoPagamento: idTipoPagamento ?? this.idTipoPagamento,
      // REMOVIDO: cópia de idTipoOrigemPedido e idTipoEntrega
      dataPedido: dataPedido ?? this.dataPedido,
      dataFimPedido: dataFimPedido ?? this.dataFimPedido,
      statusPedido: statusPedido ?? this.statusPedido,
      notificacaoVista: notificacaoVista ?? this.notificacaoVista,
      total: total ?? this.total,
      enderecoJson: enderecoJson ?? this.enderecoJson,
      valorPagoManual: valorPagoManual ?? this.valorPagoManual,
      dataFinalizacao: dataFinalizacao ?? this.dataFinalizacao,
      bairro: bairro ?? this.bairro,
      pontoReferencia: pontoReferencia ?? this.pontoReferencia,
      troco: troco ?? this.troco,
      ocultoCliente: ocultoCliente ?? this.ocultoCliente,
      itens: itens ?? this.itens,
      nomeUsuario: nomeUsuario ?? this.nomeUsuario,
    );
  }
}

// ItemPedido permanece inalterado
class ItemPedidoFields {
  static const String idItemPedido = 'id_item_pedido';
  static const String idPedido = 'id_pedido';
  static const String idProduto = 'id_produto';
  static const String quantidade = 'quantidade';
  static const String precoUnitario = 'preco_unitario';
  static const String subtotal = 'subtotal';
}

class ItemPedido {
  final int? id;
  final int idPedido;
  final int idProduto;
  final int quantidade;
  final double precoUnitario;
  final double subtotal;
  final Produto? produto;
  
  ItemPedido({
    this.id,
    required this.idPedido,
    required this.idProduto,
    required this.quantidade,
    required this.precoUnitario,
    required this.subtotal,
    this.produto,
  });

  Map<String, dynamic> toMap() {
    return {
      ItemPedidoFields.idItemPedido: id,
      ItemPedidoFields.idPedido: idPedido,
      ItemPedidoFields.idProduto: idProduto,
      ItemPedidoFields.quantidade: quantidade,
      ItemPedidoFields.precoUnitario: precoUnitario,
      ItemPedidoFields.subtotal: subtotal,
    };
  }

  factory ItemPedido.fromMap(Map<String, dynamic> map) {
    return ItemPedido(
      id: map[ItemPedidoFields.idItemPedido] as int?,
      idPedido: map[ItemPedidoFields.idPedido] as int,
      idProduto: map[ItemPedidoFields.idProduto] as int,
      quantidade: map[ItemPedidoFields.quantidade] as int,
      precoUnitario: (map[ItemPedidoFields.precoUnitario] as num).toDouble(),
      subtotal: (map[ItemPedidoFields.subtotal] as num).toDouble(),
    );
  }

  ItemPedido copyWith({
    int? id,
    int? idPedido,
    int? idProduto,
    int? quantidade,
    double? precoUnitario,
    double? subtotal,
    Produto? produto,
  }) {
    return ItemPedido(
      id: id ?? this.id,
      idPedido: idPedido ?? this.idPedido,
      idProduto: idProduto ?? this.idProduto,
      quantidade: quantidade ?? this.quantidade,
      precoUnitario: precoUnitario ?? this.precoUnitario,
      subtotal: subtotal ?? this.subtotal,
      produto: produto ?? this.produto,
    );
  }
}