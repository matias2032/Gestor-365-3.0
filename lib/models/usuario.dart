// lib/models/usuario.dart

// lib/models/usuario.dart (ADICIONE ISTO)
class UsuarioFields {
  static final List<String> values = [
    id_usuario,
    nome,
    apelido,
    email,
    senha_hash,
    telefone,
    data_cadastro,
    idprovincia,
    idcidade,
    idperfil,
    primeira_senha,
    ativo, // 💡 NOVO CAMPO
  ];

  static const String id_usuario = 'id_usuario';
  static const String nome = 'nome';
  static const String apelido = 'apelido';
  static const String email = 'email';
  static const String senha_hash = 'senha_hash';
  static const String telefone = 'telefone';
  static const String data_cadastro = 'data_cadastro';
  static const String idprovincia = 'idprovincia';
  static const String idcidade = 'idcidade';
  static const String idperfil = 'idperfil';
  static const String primeira_senha = 'primeira_senha';
  static const String ativo = 'ativo'; // 💡 NOVO CAMPO ATIVO
}
// (O resto da classe Usuario vem depois)

class Usuario {
  final int? id; // id_usuario
  final String nome;
  final String apelido;
  final String email;
  final String senhaHash;
  final String? telefone;
  final String dataCadastro;
  final int? idProvincia;
  final int? idCidade;
  final int? idPerfil;
  final int primeiraSenha; // Booleano: 1 ou 0
  final int ativo; // 💡 NOVO CAMPO: 1 (Ativo) ou 0 (Inativo/Desligado)

  Usuario({
    this.id,
    required this.nome,
    required this.apelido,
    required this.email,
    required this.senhaHash,
    this.telefone,
    required this.dataCadastro,
    this.idProvincia,
    this.idCidade,
    this.idPerfil,
    this.primeiraSenha = 1,
    this.ativo = 1, // 💡 VALOR PADRÃO: 1 (Ativo)
  });

  // 1. Converter Objeto Dart para Map (Para INSERIR ou ATUALIZAR no DB)
  Map<String, dynamic> toMap() {
    return {
      UsuarioFields.id_usuario: id,
      UsuarioFields.nome: nome,
      UsuarioFields.apelido: apelido,
      UsuarioFields.email: email,
      UsuarioFields.senha_hash: senhaHash,
      UsuarioFields.telefone: telefone,
      UsuarioFields.data_cadastro: dataCadastro,
      UsuarioFields.idprovincia: idProvincia,
      UsuarioFields.idcidade: idCidade,
      UsuarioFields.idperfil: idPerfil,
      UsuarioFields.primeira_senha: primeiraSenha,
      UsuarioFields.ativo: ativo, // 💡 INCLUSÃO DO CAMPO ATIVO
    };
  }

  // 2. Criar Objeto Dart a partir de Map (Para LER do DB)
  factory Usuario.fromMap(Map<String, dynamic> map) {
    // Usamos o null-aware operator '?? 1' para garantir que, se o campo for nulo (usuários antigos antes da migração),
    // ele seja considerado ativo por padrão.
    return Usuario(
      id: map[UsuarioFields.id_usuario] as int?,
      nome: map[UsuarioFields.nome] as String,
      apelido: map[UsuarioFields.apelido] as String,
      email: map[UsuarioFields.email] as String,
      senhaHash: map[UsuarioFields.senha_hash] as String,
      telefone: map[UsuarioFields.telefone] as String?,
      dataCadastro: map[UsuarioFields.data_cadastro] as String,
      idProvincia: map[UsuarioFields.idprovincia] as int?,
      idCidade: map[UsuarioFields.idcidade] as int?,
      idPerfil: map[UsuarioFields.idperfil] as int?,
      primeiraSenha: map[UsuarioFields.primeira_senha] as int? ?? 1,
      ativo: map[UsuarioFields.ativo] as int? ?? 1, // 💡 LEITURA DO CAMPO ATIVO
    );
  }

  // Método auxiliar para criar uma nova cópia do objeto, mudando apenas alguns campos (útil após inserção ou UPDATE)
  Usuario copyWith({
    int? id,
    String? senhaHash,
    int? primeiraSenha,
    int? ativo, // 💡 INCLUSÃO NO COPYWITH
  }) {
    return Usuario(
      id: id ?? this.id,
      nome: nome,
      apelido: apelido,
      email: email,
      senhaHash: senhaHash ?? this.senhaHash,
      telefone: telefone,
      dataCadastro: dataCadastro,
      idProvincia: idProvincia,
      idCidade: idCidade,
      idPerfil: idPerfil,
      primeiraSenha: primeiraSenha ?? this.primeiraSenha,
      ativo: ativo ?? this.ativo, // 💡 COPIA O NOVO CAMPO
    );
  }
}
