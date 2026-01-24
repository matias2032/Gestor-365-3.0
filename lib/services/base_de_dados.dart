// lib/services/base_de_dados.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/usuario.dart';
import '../models/categoria.dart';
import '../models/produto.dart'; // 💡 IMPORTAR O NOVO MODELO PRODUTO
import '../models/produto_imagem.dart';
import '../models/pedido.dart';
import 'dart:async';
import'../services/estoque_alerta_service.dart';
// Definindo a versão do DB como 2 para ativar o onUpgrade se já existir a v1
const int _dbVersion = 7;

class DatabaseService {
  // Padrão Singleton
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    // Nome do arquivo do banco
    _database = await _initDB('bar_digital_v2.db'); 
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path, 
      version: _dbVersion,
      onCreate: _createDB,      // Cria tabelas e dados iniciais
      onConfigure: _onConfigure, // Ativa Foreign Keys
      onUpgrade: _onUpgrade,    // Gerencia atualizações de versão
    );
  }

  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // ==========================================================
  // 1. MÉTODO DE MIGRAÇÃO (ON UPGRADE)
  // ==========================================================
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
  print('🔄 Iniciando Migração do DB de V$oldVersion para V$newVersion...');
  
 if (oldVersion < 3) {
    print('➕ Criando tabela movimento_estoque...');
    
    await db.execute('''
      CREATE TABLE movimento_estoque (
        id_movimento INTEGER PRIMARY KEY AUTOINCREMENT,
        id_produto INTEGER NOT NULL,
        id_usuario INTEGER NOT NULL,
        tipo_movimento TEXT NOT NULL,
        quantidade INTEGER NOT NULL,
        quantidade_anterior INTEGER NOT NULL,
        quantidade_nova INTEGER NOT NULL,
        motivo TEXT,
        data_movimento TEXT NOT NULL DEFAULT (datetime('now', 'utc')),
        FOREIGN KEY (id_produto) REFERENCES produto(id_produto) ON DELETE CASCADE,
        FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE SET NULL
      )
    ''');
    
    print('✅ Tabela movimento_estoque criada com sucesso!');
  }

    // 🔥 NOVO: Adicionar coluna device_id se estiver atualizando para v6+
  if (oldVersion < 6) {
    print('➕ Adicionando coluna device_id à tabela movimento_estoque...');
    try {
      await db.execute('ALTER TABLE movimento_estoque ADD COLUMN device_id TEXT');
      print('✅ Coluna device_id adicionada com sucesso!');
    } catch (e) {
      print('⚠️ Erro ao adicionar device_id (pode já existir): $e');
    }
  }

    print('✅ Migração concluída de V$oldVersion para V$newVersion.');
}


  // ==========================================================
  // 2. CRIAÇÃO DE TABELAS E DADOS INICIAIS (SEEDING)
  // ==========================================================
  Future _createDB(Database db, int version) async {
    
    // --- DEFINIÇÃO DE TIPOS ---
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';
    const intNullable = 'INTEGER';
    const doubleType = 'REAL NOT NULL';
    
    // --- CRIAÇÃO DAS TABELAS ---

    // 1. Localização
    await db.execute('''
      CREATE TABLE provincia (
        idprovincia $idType,
        nome_provincia $textType
      )
    ''');
    
    await db.execute('''
      CREATE TABLE cidade (
        idcidade $idType,
        nome_cidade $textType,
        idprovincia INTEGER NOT NULL,
        FOREIGN KEY (idprovincia) REFERENCES provincia(idprovincia) ON DELETE CASCADE
      )
    ''');
    
    // 2. Usuários e Perfis
    await db.execute('''
      CREATE TABLE perfil (
        idperfil $idType,
        nome_perfil $textType
      )
    ''');
    
    await db.execute('''
      CREATE TABLE usuario (
        id_usuario $idType,
        nome $textType,
        apelido $textType,
        email TEXT NOT NULL UNIQUE,
        senha_hash $textType,
        telefone $textNullable,
        ativo INTEGER DEFAULT 1,
        data_cadastro TEXT NOT NULL DEFAULT (datetime('now', 'utc')),
        idprovincia $intNullable,
        idcidade $intNullable,
        idperfil $intNullable,
        primeira_senha INTEGER DEFAULT 1,
        FOREIGN KEY (idprovincia) REFERENCES provincia(idprovincia) ON DELETE SET NULL,
        FOREIGN KEY (idcidade) REFERENCES cidade(idcidade) ON DELETE SET NULL,
        FOREIGN KEY (idperfil) REFERENCES perfil(idperfil) ON DELETE SET NULL
      )
    ''');
    
    // 3. Produtos
    await db.execute('''
      CREATE TABLE categoria (
        id_categoria $idType,
        nome_categoria $textType,
        descricao $textNullable
      )
    ''');
    
    await db.execute('''
      CREATE TABLE produto (
        id_produto $idType,
        nome_produto $textType,
        descricao $textNullable,
        preco $doubleType,
        quantidade_estoque INTEGER,
        preco_promocional REAL,
        ativo INTEGER DEFAULT 1,
        data_cadastro TEXT DEFAULT (datetime('now', 'utc'))
    
      )
    ''');
    
    await db.execute('''
      CREATE TABLE produto_categoria (
        id_produto INTEGER NOT NULL,
        id_categoria INTEGER NOT NULL,
        PRIMARY KEY (id_produto, id_categoria),
        FOREIGN KEY (id_produto) REFERENCES produto(id_produto) ON DELETE CASCADE,
        FOREIGN KEY (id_categoria) REFERENCES categoria(id_categoria) ON DELETE CASCADE
      )
    ''');
    
    await db.execute('''
      CREATE TABLE produto_imagem (
        id_imagem $idType,
        id_produto INTEGER NOT NULL,
        caminho_imagem $textType,
        legenda $textNullable,
        imagem_principal INTEGER DEFAULT 0,
        FOREIGN KEY (id_produto) REFERENCES produto(id_produto) ON DELETE CASCADE
      )
    ''');
    
    // 4. Avaliação
    await db.execute('''
      CREATE TABLE avaliacao (
        id_avaliacao $idType,
        id_usuario INTEGER NOT NULL,
        id_produto INTEGER NOT NULL,
        classificacao INTEGER NOT NULL,
        comentario $textNullable,
        data_avaliacao TEXT NOT NULL DEFAULT (datetime('now', 'utc')),
        UNIQUE(id_usuario, id_produto),
        FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE CASCADE,
        FOREIGN KEY (id_produto) REFERENCES produto(id_produto) ON DELETE CASCADE
      )
    ''');
    
    // 5. Pedidos
    await db.execute('''
      CREATE TABLE tipo_pagamento (
        idtipo_pagamento $idType,
        tipo_pagamento $textType
      )
    ''');
    
await db.execute('''
  CREATE TABLE pedido (
    id_pedido INTEGER PRIMARY KEY AUTOINCREMENT,
    reference TEXT UNIQUE,
    id_usuario INTEGER NOT NULL,
    telefone TEXT,
    email TEXT,
    idtipo_pagamento INTEGER NOT NULL,
    data_pedido TEXT NOT NULL DEFAULT (datetime('now', 'utc')),
    data_fim_pedido TEXT,
    status_pedido TEXT DEFAULT 'por finalizar',
    notificacao_vista INTEGER NOT NULL DEFAULT 0,
    total REAL NOT NULL,
    endereco_json TEXT,
    valor_pago_manual REAL DEFAULT 0.00,
    data_finalizacao TEXT,
    bairro TEXT,
    ponto_referencia TEXT,
    troco REAL DEFAULT 0.00,
    oculto_cliente INTEGER DEFAULT 0,
    FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE CASCADE,
    FOREIGN KEY (idtipo_pagamento) REFERENCES tipo_pagamento(idtipo_pagamento)
  )
''');
    
    await db.execute('''
      CREATE TABLE item_pedido (
        id_item_pedido $idType,
        id_pedido INTEGER NOT NULL,
        id_produto INTEGER NOT NULL,
        quantidade INTEGER NOT NULL,
        preco_unitario $doubleType,
        subtotal $doubleType,
        FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido) ON DELETE CASCADE,
        FOREIGN KEY (id_produto) REFERENCES produto(id_produto)
      )
    ''');

    await db.execute('''
      CREATE TABLE rastreamento_pedido (
        id_rastreamento $idType,
        id_pedido INTEGER NOT NULL,
        status_pedido $textType,
        data_hora TEXT NOT NULL DEFAULT (datetime('now', 'utc')),
        FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido) ON DELETE CASCADE
      )
    ''');
    
    await db.execute('''
      CREATE TABLE pedido_cancelamento (
        id_cancelamento $idType,
        id_pedido INTEGER NOT NULL,
        motivo $textNullable,
        id_usuario_cancelou INTEGER NOT NULL,
        data_cancelamento TEXT NOT NULL DEFAULT (datetime('now', 'utc')),
        FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido) ON DELETE CASCADE,
        FOREIGN KEY (id_usuario_cancelou) REFERENCES usuario(id_usuario)
      )
    ''');
    
    // 6. Pagamentos
    await db.execute('''
      CREATE TABLE payments_local (
        id $idType,
        reference TEXT NOT NULL UNIQUE,
        amount $doubleType,
        status TEXT DEFAULT 'pendente',
        transaction_id $textNullable,
        paid_at $textNullable,
        created_at TEXT DEFAULT (datetime('now', 'utc')),
        id_pedido $intNullable,
        id_usuario $intNullable,
        FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido) ON DELETE SET NULL,
        FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE SET NULL
      )
    ''');
    
    // 7. Fidelidade
    await db.execute('''
      CREATE TABLE fidelidade (
        id_fidelidade $idType,
        id_usuario INTEGER NOT NULL UNIQUE,
        pontos INTEGER DEFAULT 0,
        data_ultima_compra TEXT NOT NULL DEFAULT (datetime('now', 'utc')),
        data_expiracao $textNullable,
        FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE CASCADE
      )
    ''');
    
    // 8. Segurança
    await db.execute('''
      CREATE TABLE historico_senhas (
        id_historico $idType,
        id_usuario INTEGER NOT NULL,
        senha_hash $textType,
        data_alteracao TEXT DEFAULT (datetime('now', 'utc')),
        FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE CASCADE
      )
    ''');
    
    await db.execute('''
      CREATE TABLE password_resets (
        id_reset $idType,
        id_usuario INTEGER NOT NULL,
        token_hash $textType,
        expires_at $textType,
        created_at TEXT DEFAULT (datetime('now', 'utc')),
        used_at $textNullable,
        ip_solicitacao $textNullable,
        user_agent $textNullable,
        FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE CASCADE
      )
    ''');
    
    // 9. Notificações e Logs
    await db.execute('''
      CREATE TABLE notificacao (
        id_notificacao $idType,
        tipo $textNullable,
        mensagem $textNullable,
        id_pedido $intNullable,
        lida INTEGER DEFAULT 0,
        data_criacao TEXT NOT NULL DEFAULT (datetime('now', 'utc')),
        FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido) ON DELETE CASCADE
      )
    ''');
    
    await db.execute('''
      CREATE TABLE logs (
        id_log $idType,
        id_usuario $intNullable,
        acao $textNullable,
        data_hora TEXT DEFAULT (datetime('now', 'utc')),
        FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE SET NULL
      )
    ''');
    // 10. Movimentos de Estoque Manual
await db.execute('''
  CREATE TABLE movimento_estoque (
    id_movimento $idType,
    id_produto INTEGER NOT NULL,
    id_usuario INTEGER NOT NULL,
    tipo_movimento $textType,
    quantidade INTEGER NOT NULL,
    quantidade_anterior INTEGER NOT NULL,
    quantidade_nova INTEGER NOT NULL,
    motivo $textNullable,
    device_id $textNullable,
    data_movimento TEXT NOT NULL DEFAULT (datetime('now', 'utc')),
    FOREIGN KEY (id_produto) REFERENCES produto(id_produto) ON DELETE CASCADE,
    FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE SET NULL
  )
''');

    // --- INSERÇÃO DE DADOS INICIAIS (SEEDING) ---
    
    // 10.1 Tipos de Pagamento
    await db.rawInsert("INSERT OR IGNORE INTO tipo_pagamento (tipo_pagamento) VALUES (?)", ['Dinheiro vivo']);
    await db.rawInsert("INSERT OR IGNORE INTO tipo_pagamento (tipo_pagamento) VALUES (?)", ['VISA']);
    await db.rawInsert("INSERT OR IGNORE INTO tipo_pagamento (tipo_pagamento) VALUES (?)", ['M-Pesa']);
    await db.rawInsert("INSERT OR IGNORE INTO tipo_pagamento (tipo_pagamento) VALUES (?)", ['E-Mola']);

    // 10.2 Perfis (Com IDs explícitos)
    await db.rawInsert("INSERT OR IGNORE INTO perfil (idperfil, nome_perfil) VALUES (1, 'Administrador')");
    await db.rawInsert("INSERT OR IGNORE INTO perfil (idperfil, nome_perfil) VALUES (2, 'Gerente')");
    await db.rawInsert("INSERT OR IGNORE INTO perfil (idperfil, nome_perfil) VALUES (3, 'Funcionário')");
    await db.rawInsert("INSERT OR IGNORE INTO perfil (idperfil, nome_perfil) VALUES (4, 'Cliente')");

    // ==========================================================
    // 10.3 SEEDING DE USUÁRIOS ESPECIAIS (ADMIN E GERENTE)
    // ==========================================================
    
    // ⚠️ SUBSTITUA PELOS HASHES REAIS GERADOS PELO FLUTTER_BCRYPT ⚠️
    // Ex: '$2a$10$XyZ...'
    const String hashMatias = r'$2b$10$rkq1G/KhzRox2m5jSaYmpOGUfHwq.KzS1LEd2cBJdn9A7NuZRZeua'; 
   
    // ADMIN: Matias
    await db.rawInsert('''
      INSERT OR IGNORE INTO usuario (
        nome, apelido, email, telefone, senha_hash, idperfil, primeira_senha
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', [
      'Matias', 
      'Matavel', 
      'matiasmatavel1232@gmail.com', 
      '876821594', 
      hashMatias, // Senha hash para: mt1232
      1, // Perfil: Administrador
      0
    ]);



    // 10.4 Províncias
    final List<Map<String, dynamic>> provincias = [
      {'idprovincia': 1, 'nome_provincia': 'Maputo'},
      {'idprovincia': 2, 'nome_provincia': 'Gaza'},
      {'idprovincia': 3, 'nome_provincia': 'Inhambane'},
    ];
    for (var p in provincias) {
      await db.rawInsert("INSERT OR IGNORE INTO provincia (idprovincia, nome_provincia) VALUES (?, ?)", [p['idprovincia'], p['nome_provincia']]);
    }

    // 10.5 Cidades
    final List<Map<String, dynamic>> cidades = [
      {'idcidade': 1, 'nome_cidade': 'Maputo', 'idprovincia': 1},
      {'idcidade': 2, 'nome_cidade': 'Matola', 'idprovincia': 1},
      {'idcidade': 3, 'nome_cidade': 'Xai-xai', 'idprovincia': 2},
    ];
    for (var c in cidades) {
      await db.rawInsert("INSERT OR IGNORE INTO cidade (idcidade, nome_cidade, idprovincia) VALUES (?, ?, ?)", [c['idcidade'], c['nome_cidade'], c['idprovincia']]);
    }
    
    // 11. TRIGGERS
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_payment_status_update
      AFTER UPDATE ON payments_local
      WHEN NEW.status = 'pago' AND OLD.status != 'pago'
      BEGIN
        UPDATE pedido
        SET status_pedido = 'Em preparação',
          data_finalizacao = datetime('now', 'localtime')
        WHERE id_pedido = NEW.id_pedido;
      END;
    ''');
  }

  // Método para fechar o banco
  Future close() async {
    final db = await instance.database;
    if (db.isOpen) {
      db.close();
    }
  }

  // ======================================
  // MÉTODOS CRUD (CREATE, READ, UPDATE, DELETE)
  // ======================================

  // C: CREATE
  Future<Usuario> createUsuario(Usuario usuario) async {
    final db = await instance.database;
    
    final id = await db.insert(
      'usuario', 
      usuario.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return usuario.copyWith(id: id); 
  }

  // R: READ (Por ID)
  Future<Usuario?> readUsuario(int id) async {
    final db = await instance.database;

    final maps = await db.query(
      'usuario',
      columns: UsuarioFields.values,
      where: 'id_usuario = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Usuario.fromMap(maps.first);
    } else {
      return null;
    }
  }

  // R: READ (Login por Email)
  Future<Usuario?> readUsuarioByEmail(String email) async {
    final db = await instance.database;

    final maps = await db.query(
      'usuario',
      where: 'email = ?',
      whereArgs: [email],
    );

    if (maps.isNotEmpty) {
      return Usuario.fromMap(maps.first); 
    } else {
      return null;
    }
  }

  // U: UPDATE
  Future<int> updateUsuario(Usuario usuario) async {
    final db = await instance.database;

    return db.update(
      'usuario',
      usuario.toMap(),
      where: 'id_usuario = ?',
      whereArgs: [usuario.id],
    );
  }

  // D: DELETE
  Future<int> deleteUsuario(int id) async {
    final db = await instance.database;

    return await db.delete(
      'usuario',
      where: 'id_usuario = ?',
      whereArgs: [id],
    );
  }

  Future<List<Usuario>> readAllUsuarios() async {
    final db = await instance.database;

    // Ordena pelo ID para que o Administrador (ID 1) apareça primeiro
    const orderBy = 'id_usuario ASC'; 
    
    final result = await db.query('usuario', orderBy: orderBy);

    return result.map((json) => Usuario.fromMap(json)).toList();
  }

  // lib/services/base_de_dados.dart (Adicione este método)

// ... (dentro da classe DatabaseService)

// R: READ (Login por Email, Telefone ou Apelido)
Future<Usuario?> readUsuarioByCredencial(String credencial) async {
  final db = await instance.database;

  final maps = await db.query(
    'usuario',
    where: 'email = ? OR telefone = ? OR apelido = ?', // BUSCA OS 3 CAMPOS
    whereArgs: [credencial, credencial, credencial], // USA A MESMA STRING
    limit: 1, // Só precisamos do primeiro match
  );

  if (maps.isNotEmpty) {
    return Usuario.fromMap(maps.first);
  } else {
    return null;
  }
}

Future<int> toggleAtivoUsuario(int id, bool isActive) async {
  final db = await instance.database;

  final data = {
    'ativo': isActive ? 1 : 0, // 1 para ativo, 0 para inativo (desligado)
  };

  return db.update(
    'usuario',
    data,
    where: 'id_usuario = ?',
    whereArgs: [id],
  );
}

Future<int> toggleAtivoProduto(int idProduto, bool isActive) async {
  final db = await instance.database;

  final data = {
    'ativo': isActive ? 1 : 0,
  };

  return db.update(
    'produto',
    data,
    where: 'id_produto = ?',
    whereArgs: [idProduto],
  );
}

// lib/services/base_de_dados.dart



// --- MÉTODOS CRUD DE CATEGORIA ---

// 1. Criar Categoria e Associar Produtos
Future<int> createCategoria(Categoria categoria, List<int> idsProdutos) async {
    final db = await instance.database;
    
    // Inicia uma transação para garantir que a categoria e as associações sejam criadas ou nenhuma o seja
    return await db.transaction((txn) async {
        // 1.1. Inserir a nova Categoria
        final idCategoria = await txn.insert(
            'categoria', 
            categoria.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
        );
        
        // 1.2. Associar Produtos (se existirem IDs)
        if (idsProdutos.isNotEmpty) {
            for (final idProduto in idsProdutos) {
                await txn.insert(
                    'produto_categoria',
                    {
                        'id_produto': idProduto,
                        'id_categoria': idCategoria,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace,
                );
            }
        }
        return idCategoria;
    });
}

// 2. Ler todas as Categorias com Seus Produtos Associados
Future<List<Categoria>> readAllCategoriasWithProdutos() async {
    final db = await instance.database;
    final categoriasMaps = await db.query('categoria', orderBy: 'nome_categoria ASC');
    final List<Categoria> categoriasComProdutos = [];
    
    for (var catMap in categoriasMaps) {
        final idCategoria = catMap[CategoriaFields.idCategoria] as int;
        
        // Junta produto_categoria (p_c) com produto (p)
        final produtosMaps = await db.rawQuery('''
            SELECT p.* FROM produto_categoria p_c
            INNER JOIN produto p ON p_c.id_produto = p.id_produto
            WHERE p_c.id_categoria = ?
        ''', [idCategoria]);
        
        // 💡 AGORA USA Produto.fromMap
        final produtos = produtosMaps.map((p) => Produto.fromMap(p)).toList(); 
        
        // Cria o objeto Categoria com a lista de produtos
        categoriasComProdutos.add(
            Categoria.fromMap(catMap)
                .copyWith(produtosAssociados: produtos)
        );
    }
    return categoriasComProdutos;
}

// 4. Ler Todos os Produtos Simples (AGORA Produto Simples, mantendo apenas ID e Nome)
Future<List<Produto>> readAllProdutosSimples() async {
    final db = await instance.database;
    // Seleciona todos os campos, mas a tela só usará ID e NOME
    final produtosMaps = await db.query(
        'produto',
        // 💡 FILTRO IMPORTANTE: Apenas produtos ativos devem ser associáveis
        where: 'ativo = 1', 
        orderBy: 'nome_produto ASC',
    );
    // 💡 Usa o construtor Produto.fromMap que pega todos os campos
    return produtosMaps.map((map) => Produto.fromMap(map)).toList(); 
}

// 5. Ler Categoria e seus Produtos por ID (Para Edição)
Future<Categoria?> readCategoriaWithProdutosById(int idCategoria) async {
    final db = await instance.database;
    
    final catMaps = await db.query(
        'categoria',
        where: 'id_categoria = ?',
        whereArgs: [idCategoria],
    );
    
    if (catMaps.isEmpty) return null;
    
    final catMap = catMaps.first;
    
    // Busca os produtos associados
    final produtosMaps = await db.rawQuery('''
        SELECT p.* FROM produto_categoria p_c
        INNER JOIN produto p ON p_c.id_produto = p.id_produto
        WHERE p_c.id_categoria = ?
    ''', [idCategoria]);
    
    // 💡 AGORA USA Produto.fromMap
    final produtos = produtosMaps.map((p) => Produto.fromMap(p)).toList(); 
    
    return Categoria.fromMap(catMap).copyWith(produtosAssociados: produtos);
}


// 6. Deletar Categoria (ON DELETE CASCADE cuidará das associações)
Future<int> deleteCategoria(int idCategoria) async {
    final db = await instance.database;
    // Devido ao ON DELETE CASCADE, as linhas em produto_categoria são removidas automaticamente.
    return await db.delete(
        'categoria',
        where: 'id_categoria = ?',
        whereArgs: [idCategoria],
    );
}

// 7. Atualizar Categoria e Associações
Future<int> updateCategoria(Categoria categoria, List<int> idsProdutos) async {
    final db = await instance.database;

    if (categoria.id == null) return 0;

    return await db.transaction((txn) async {
        // 7.1. Atualiza o nome/descrição da Categoria
        final rowsAffected = await txn.update(
            'categoria', 
            categoria.toMap(),
            where: 'id_categoria = ?',
            whereArgs: [categoria.id],
        );

        // 7.2. Remove todas as associações antigas para reconstruir as novas
        await txn.delete(
            'produto_categoria',
            where: 'id_categoria = ?',
            whereArgs: [categoria.id],
        );

        // 7.3. Insere as novas associações
        if (idsProdutos.isNotEmpty) {
            for (final idProduto in idsProdutos) {
                await txn.insert(
                    'produto_categoria',
                    {
                        'id_produto': idProduto,
                        'id_categoria': categoria.id,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace,
                );
            }
        }
        return rowsAffected;
    });
}

Future<List<Categoria>> readAllCategoriasSimples() async {
    final db = await instance.database;
    final categoriasMaps = await db.query(
        'categoria',
        columns: [CategoriaFields.idCategoria, CategoriaFields.nomeCategoria],
        orderBy: 'nome_categoria ASC',
    );
    // Nota: O Categoria.fromMap precisa lidar com campos nulos se apenas ID e Nome são buscados.
    return categoriasMaps.map((map) => Categoria.fromMap(map)).toList(); 
}


// 1. Criar Produto, Associações de Categoria e Imagem
Future<int> createProduto(
  Produto produto, 
  List<int> idsCategorias, 
  List<ProdutoImagem> imagens
) async {
    final db = await instance.database;
    
    return await db.transaction((txn) async {
        // 1.1. Inserir o novo Produto
        final idProduto = await txn.insert(
            'produto', 
            produto.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
        );
        
        // 1.2. Associar Categorias
        if (idsCategorias.isNotEmpty) {
            for (final idCategoria in idsCategorias) {
                await txn.insert(
                    'produto_categoria',
                    {
                        'id_produto': idProduto,
                        'id_categoria': idCategoria,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace,
                );
            }
        }

        // 1.3. Inserir Imagens
        if (imagens.isNotEmpty) {
             // Garante que a primeira imagem seja principal se nenhuma estiver marcada
             if (!imagens.any((img) => img.isPrincipal)) {
                 imagens[0] = ProdutoImagem(
                     idProduto: idProduto, 
                     caminho: imagens[0].caminho,
                     legenda: imagens[0].legenda,
                     isPrincipal: true, // Define a primeira como principal por padrão
                 );
             }
             
            for (final imagem in imagens) {
                await txn.insert(
                    'produto_imagem',
                    imagem.copyWith(idProduto: idProduto).toMap(), // Garante que idProduto está correto
                    conflictAlgorithm: ConflictAlgorithm.replace,
                );
            }
        }
          EstoqueAlertaService.instance.verificarEstoque();
        
        return idProduto;
    });
}

// 2. Ler todos os Produtos com Categorias e Imagem Principal
Future<List<Produto>> readAllProdutosWithAssoc() async {
    final db = await instance.database;
    final produtosMaps = await db.query('produto', orderBy: 'nome_produto ASC');
    final List<Produto> produtosComDetalhes = [];
    
    for (var prodMap in produtosMaps) {
        final idProduto = prodMap[ProdutoFields.idProduto] as int;
        
        // A. Buscar Categorias Associadas (apenas ID e Nome)
        final categoriasMaps = await db.rawQuery('''
            SELECT c.id_categoria, c.nome_categoria FROM produto_categoria p_c
            INNER JOIN categoria c ON p_c.id_categoria = c.id_categoria
            WHERE p_c.id_produto = ?
        ''', [idProduto]);
        
        final categorias = categoriasMaps.map((c) => Categoria.fromMap(c)).toList(); 
        
        // B. Buscar Imagem Principal
        final imagemPrincipalMaps = await db.query(
            'produto_imagem',
            where: 'id_produto = ? AND imagem_principal = 1',
            whereArgs: [idProduto],
            limit: 1,
        );
        
        // C. Cria o objeto Produto completo
        final List<ProdutoImagem> imagens = imagemPrincipalMaps.isNotEmpty 
            ? [ProdutoImagem.fromMap(imagemPrincipalMaps.first)] 
            : [];

        produtosComDetalhes.add(
            Produto.fromMap(prodMap).copyWith(
                categoriasAssociadas: categorias,
                imagens: imagens, // Coloca a principal na lista de imagens para acesso fácil
            )
        );
    }
    return produtosComDetalhes;
}

// 3. Ler Produto com Categorias e Todas as Imagens por ID (Para Edição)
Future<Produto?> readProdutoWithDetailsById(int idProduto) async {
    final db = await instance.database;
    
    // 3.1. Busca os dados do Produto
    final prodMaps = await db.query(
        'produto',
        where: 'id_produto = ?',
        whereArgs: [idProduto],
    );
    
    if (prodMaps.isEmpty) return null;
    final prodMap = prodMaps.first;
    
    // 3.2. Busca Categorias Associadas
    final categoriasMaps = await db.rawQuery('''
        SELECT c.id_categoria, c.nome_categoria FROM produto_categoria p_c
        INNER JOIN categoria c ON p_c.id_categoria = c.id_categoria
        WHERE p_c.id_produto = ?
    ''', [idProduto]);
    final categorias = categoriasMaps.map((c) => Categoria.fromMap(c)).toList(); 

    // 3.3. Busca TODAS as Imagens
    final imagensMaps = await db.query(
        'produto_imagem',
        where: 'id_produto = ?',
        whereArgs: [idProduto],
        orderBy: 'imagem_principal DESC', // Garante que a principal venha primeiro
    );
    final imagens = imagensMaps.map((i) => ProdutoImagem.fromMap(i)).toList();
    
    return Produto.fromMap(prodMap).copyWith(
        categoriasAssociadas: categorias,
        imagens: imagens,
    );
}

// 4. Deletar Produto
Future<int> deleteProduto(int idProduto) async {
    final db = await instance.database;
    // ON DELETE CASCADE no DB cuidará de produto_categoria e produto_imagem
    return await db.delete(
        'produto',
        where: 'id_produto = ?',
        whereArgs: [idProduto],
    );
}

// 5. Atualizar Produto, Associações de Categoria e Imagem
Future<int> updateProduto(
    Produto produto, 
    List<int> idsCategorias, 
    List<ProdutoImagem> imagens,
) async {
    final db = await instance.database;

    if (produto.id == null) return 0;

    return await db.transaction((txn) async {
        final idProduto = produto.id!;
        
        // 5.1. Atualiza os dados do Produto
        final rowsAffected = await txn.update(
            'produto', 
            produto.toMap(),
            where: 'id_produto = ?',
            whereArgs: [idProduto],
        );

        // 5.2. ATUALIZAÇÃO DE CATEGORIAS: Remove antigas e insere novas
        await txn.delete('produto_categoria', where: 'id_produto = ?', whereArgs: [idProduto]);
        if (idsCategorias.isNotEmpty) {
            for (final idCategoria in idsCategorias) {
                await txn.insert('produto_categoria', {'id_produto': idProduto, 'id_categoria': idCategoria});
            }
        }
        
        // 5.3. ATUALIZAÇÃO DE IMAGENS: Remove antigas e insere novas
        await txn.delete('produto_imagem', where: 'id_produto = ?', whereArgs: [idProduto]);
        if (imagens.isNotEmpty) {
             // Garante que pelo menos uma é principal (a primeira, se não houver)
             if (!imagens.any((img) => img.isPrincipal)) {
                 imagens[0] = imagens[0].copyWith(isPrincipal: true);
             }
            for (final imagem in imagens) {
                await txn.insert(
                    'produto_imagem',
                    imagem.copyWith(idProduto: idProduto).toMap(),
                );
            }
        }
  EstoqueAlertaService.instance.verificarEstoque();
        return rowsAffected;
    });
}
// 1. Dados para o Gráfico de Pizza (Vendas por Categoria)
  Future<List<Map<String, dynamic>>> getVendasPorCategoria(String dataInicio) async {
    final db = await instance.database;
    // Junta Pedido -> Item -> Produto -> Categoria
    // Filtra pela data e agrupa pelo nome da categoria
    return await db.rawQuery('''
      SELECT c.nome_categoria, SUM(ip.subtotal) as total_vendas
      FROM item_pedido ip
      JOIN pedido ped ON ip.id_pedido = ped.id_pedido
      JOIN produto p ON ip.id_produto = p.id_produto
      JOIN produto_categoria pc ON p.id_produto = pc.id_produto
      JOIN categoria c ON pc.id_categoria = c.id_categoria
      WHERE ped.data_pedido >= ? AND ped.status_pedido != 'cancelado'
      GROUP BY c.nome_categoria
      ORDER BY total_vendas DESC
    ''', [dataInicio]);
  }

  // 2. Dados para o Gráfico de Barras (Vendas por Período)
  // Agrupa por dia para ver a evolução
  Future<List<Map<String, dynamic>>> getVendasCronologicas(String dataInicio) async {
    final db = await instance.database;
    // Agrupa vendas por data (YYYY-MM-DD)
    return await db.rawQuery('''
      SELECT substr(data_pedido, 1, 10) as data, SUM(total) as total_vendas
      FROM pedido
      WHERE data_pedido >= ? AND status_pedido != 'cancelado'
      GROUP BY substr(data_pedido, 1, 10)
      ORDER BY data ASC
    ''', [dataInicio]);
  }

// 1. Criar Pedido e Debitar Estoque
// 1. Criar Pedido e Debitar Estoque (versão segura: usa txn para todas as queries dentro da transação)
// 1. Criar Pedido e Debitar Estoque (versão corrigida: total calculado APÓS inserir todos os itens)
Future<int> createPedido(Pedido pedido, List<ItemPedido> itens) async {
  final db = await instance.database;

  return await db.transaction((txn) async {
    // 1.1. Verificar estoque ANTES de criar o pedido (USANDO txn para evitar deadlock)
    for (final item in itens) {
      // Busca apenas o campo quantidade_estoque e nome_produto com txn
      final produtoRows = await txn.rawQuery(
        'SELECT quantidade_estoque, nome_produto, preco FROM produto WHERE id_produto = ?',
        [item.idProduto],
      );

      if (produtoRows.isEmpty) {
        // Produto não encontrado -> aborta
        throw Exception('Produto ID ${item.idProduto} não encontrado.');
      }

      final row = produtoRows.first;
      // quantidade_estoque pode ser null no DB (coluna não inicializada)
      final estoqueDisponivel = row['quantidade_estoque'] is int
          ? row['quantidade_estoque'] as int
          : (row['quantidade_estoque'] == null ? null : (row['quantidade_estoque'] as num).toInt());

      if (estoqueDisponivel == null || estoqueDisponivel < item.quantidade) {
        final nomeProduto = row['nome_produto']?.toString() ?? 'Produto ID ${item.idProduto}';
        throw Exception(
          'Estoque insuficiente para $nomeProduto. '
          'Disponível: ${estoqueDisponivel ?? 0}, Solicitado: ${item.quantidade}'
        );
      }
    }

    // 🔥 CORREÇÃO 1: Criar o pedido com total ZERO (será recalculado após inserir itens)
    final pedidoTemp = pedido.copyWith(total: 0.0);
    final idPedido = await txn.insert('pedido', pedidoTemp.toMap());

    // 🔥 CORREÇÃO 2: Inserir TODOS os itens ANTES de calcular o total
    for (final item in itens) {
      // Ajusta item para ter idPedido
      final itemToInsert = item.copyWith(idPedido: idPedido);

      await txn.insert(
        'item_pedido',
        itemToInsert.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Debitar estoque - usa rawUpdate com txn
      await txn.rawUpdate(
        'UPDATE produto SET quantidade_estoque = quantidade_estoque - ? WHERE id_produto = ?',
        [item.quantidade, item.idProduto],
      );

          }

    // 🔥 CORREÇÃO 3: Recalcular total APÓS inserir TODOS os itens
    final totalResult = await txn.rawQuery(
      'SELECT SUM(subtotal) as total FROM item_pedido WHERE id_pedido = ?',
      [idPedido],
    );
    
    final totalCorreto = (totalResult.first['total'] as num?)?.toDouble() ?? 0.0;
    
    // 🔥 CORREÇÃO 4: Atualizar o pedido com o total correto
    await txn.update(
      'pedido',
      {'total': totalCorreto},
      where: 'id_pedido = ?',
      whereArgs: [idPedido],
    );

    print('✅ Pedido #$idPedido criado com ${itens.length} itens. Total: MZN ${totalCorreto.toStringAsFixed(2)}');

    return idPedido;
  });
}



// 2. Ler todos os pedidos "por finalizar" do usuário
Future<List<Pedido>> readPedidosPorFinalizar(int idUsuario) async {
  final db = await instance.database;
  
  final maps = await db.query(
    'pedido',
    where: 'id_usuario = ? AND status_pedido = ?', // ✅ JÁ ESTÁ CORRETO
    whereArgs: [idUsuario, 'por finalizar'],
    orderBy: 'data_pedido DESC',
  );
  
  final List<Pedido> pedidos = [];
  
  for (var pedidoMap in maps) {
    final pedido = Pedido.fromMap(pedidoMap);
    
    // Buscar itens do pedido
    final itens = await _readItensPedido(pedido.id!);
    
    pedidos.add(pedido.copyWith(itens: itens));
  }
  
  return pedidos;
}
// 3. Ler pedido com detalhes (itens e produtos)
Future<Pedido?> readPedidoComDetalhes(int idPedido) async {
  final db = await instance.database;
  
  final maps = await db.query(
    'pedido',
    where: 'id_pedido = ?',
    whereArgs: [idPedido],
  );
  
  if (maps.isEmpty) return null;
  
  final pedido = Pedido.fromMap(maps.first);
  final itens = await _readItensPedidoComProdutos(idPedido);
  
  return pedido.copyWith(itens: itens);
}

// 4. Auxiliar: Ler itens do pedido (sem produto)
Future<List<ItemPedido>> _readItensPedido(int idPedido) async {
  final db = await instance.database;
  
  final maps = await db.query(
    'item_pedido',
    where: 'id_pedido = ?',
    whereArgs: [idPedido],
  );
  
  return maps.map((map) => ItemPedido.fromMap(map)).toList();
}

// 5. Auxiliar: Ler itens do pedido COM dados do produto
// 5. Auxiliar: Ler itens do pedido COM dados do produto
Future<List<ItemPedido>> _readItensPedidoComProdutos(int idPedido) async {
  final db = await instance.database;
  
  // 🔥 CORREÇÃO: Query otimizada sem DISTINCT
  final maps = await db.rawQuery('''
    SELECT 
      ip.*,
      p.nome_produto,
      p.preco,
      p.quantidade_estoque,
      pi.caminho_imagem
    FROM item_pedido ip
    INNER JOIN produto p ON ip.id_produto = p.id_produto
    LEFT JOIN produto_imagem pi ON p.id_produto = pi.id_produto AND pi.imagem_principal = 1
    WHERE ip.id_pedido = ?
    ORDER BY ip.id_item_pedido
  ''', [idPedido]);
  
  final List<ItemPedido> itens = [];
  
  for (var map in maps) {
    final item = ItemPedido.fromMap(map);
    
    // 🔥 GARANTIR que o nome do produto NUNCA seja nulo
    final nomeProduto = map['nome_produto'] as String? ?? 'Produto Desconhecido';
    final caminhoImagem = map['caminho_imagem'] as String?;
    
    // Criar objeto Produto com TODOS os dados
    final produto = Produto(
      id: map['id_produto'] as int,
      nome: nomeProduto, // 🔥 SEMPRE terá um nome
      preco: (map['preco'] as num).toDouble(),
      quantidadeEstoque: map['quantidade_estoque'] as int?,
      dataCadastro: '',
      imagens: caminhoImagem != null && caminhoImagem.isNotEmpty
          ? [ProdutoImagem(
              idProduto: map['id_produto'] as int,
              caminho: caminhoImagem,
              isPrincipal: true,
            )]
          : [], // Lista vazia se não houver imagem
    );
    
    itens.add(item.copyWith(produto: produto));
  }
  
  return itens;
}
// 6. Atualizar quantidade de item (e estoque)
// 6. Atualizar quantidade de item (e estoque) - VERSÃO CORRIGIDA
Future<void> updateQuantidadeItem(int idItemPedido, int novaQuantidade) async {
  final db = await instance.database;
  
  if (novaQuantidade < 1) {
    throw Exception('Quantidade deve ser maior que zero');
  }
  
  await db.transaction((txn) async {
    // Buscar item atual
    final itemMaps = await txn.query(
      'item_pedido',
      where: 'id_item_pedido = ?',
      whereArgs: [idItemPedido],
    );
    
    if (itemMaps.isEmpty) {
      throw Exception('Item não encontrado.');
    }
    
    final itemAtual = ItemPedido.fromMap(itemMaps.first);
    final diferencaQuantidade = novaQuantidade - itemAtual.quantidade;
    
    // 🔥 CRÍTICO: Verificar estoque SOMENTE se AUMENTAR quantidade
    if (diferencaQuantidade > 0) {
      final produtoMaps = await txn.query(
        'produto',
        columns: ['quantidade_estoque', 'nome_produto'],
        where: 'id_produto = ?',
        whereArgs: [itemAtual.idProduto],
      );
      
      if (produtoMaps.isNotEmpty) {
        final estoqueDisponivel = produtoMaps.first['quantidade_estoque'] as int?;
        
        if (estoqueDisponivel == null || estoqueDisponivel < diferencaQuantidade) {
          throw Exception(
            'Estoque insuficiente. Disponível: ${estoqueDisponivel ?? 0}'
          );
        }
      }
    }
    
    // Atualizar item
    final novoSubtotal = novaQuantidade * itemAtual.precoUnitario;
    await txn.update(
      'item_pedido',
      {
        'quantidade': novaQuantidade,
        'subtotal': novoSubtotal,
      },
      where: 'id_item_pedido = ?',
      whereArgs: [idItemPedido],
    );
    
    // 🔥 CORREÇÃO: Atualizar estoque APENAS pela diferença
    if (diferencaQuantidade != 0) {
      await txn.rawUpdate(
        'UPDATE produto SET quantidade_estoque = quantidade_estoque - ? WHERE id_produto = ?',
        [diferencaQuantidade, itemAtual.idProduto],
      );
    }
    
    // Recalcular total do pedido
    await _recalcularTotalPedido(txn, itemAtual.idPedido);
  });
  
  notificarMudancaEstoque();
}

// 7. Auxiliar: Recalcular total do pedido
Future<void> _recalcularTotalPedido(Transaction txn, int idPedido) async {
  final resultado = await txn.rawQuery(
    'SELECT SUM(subtotal) as total FROM item_pedido WHERE id_pedido = ?',
    [idPedido],
  );
  
  final total = (resultado.first['total'] as num?)?.toDouble() ?? 0.0;
  
  await txn.update(
    'pedido',
    {'total': total},
    where: 'id_pedido = ?',
    whereArgs: [idPedido],
  );
}

// 8. Remover item do pedido (e estornar estoque)
Future<void> deleteItemPedido(int idItemPedido) async {
  final db = await instance.database;
  
  await db.transaction((txn) async {
    // Buscar item
    final itemMaps = await txn.query(
      'item_pedido',
      where: 'id_item_pedido = ?',
      whereArgs: [idItemPedido],
    );
    
    if (itemMaps.isEmpty) {
      throw Exception('Item não encontrado.');
    }
    
    final item = ItemPedido.fromMap(itemMaps.first);
    
    // Estornar estoque
    await txn.rawUpdate(
      'UPDATE produto SET quantidade_estoque = quantidade_estoque + ? WHERE id_produto = ?',
      [item.quantidade, item.idProduto],
    );
    
    // Remover item
    await txn.delete(
      'item_pedido',
      where: 'id_item_pedido = ?',
      whereArgs: [idItemPedido],
    );
    
    // Recalcular total
    await _recalcularTotalPedido(txn, item.idPedido);
    
    // Se não restarem itens, deletar o pedido
    final countResult = await txn.rawQuery(
      'SELECT COUNT(*) as count FROM item_pedido WHERE id_pedido = ?',
      [item.idPedido],
    );
    
    final count = countResult.first['count'] as int;
    if (count == 0) {
      await txn.delete(
        'pedido',
        where: 'id_pedido = ?',
        whereArgs: [item.idPedido],
      );
    }
  });
}

// 9. Cancelar pedido (e estornar estoque) - VERSÃO CORRIGIDA
Future<void> cancelarPedido(int idPedido, String motivo, int idUsuarioCancelou) async {
  final db = await instance.database;
  
  try {
    await db.transaction((txn) async {
      // Buscar itens para estornar estoque (usando txn)
      final itensMaps = await txn.query(
        'item_pedido',
        where: 'id_pedido = ?',
        whereArgs: [idPedido],
      );
      
      // Estornar estoque para cada item
      for (final itemMap in itensMaps) {
        final quantidade = itemMap['quantidade'] as int;
        final idProduto = itemMap['id_produto'] as int;
        
        await txn.rawUpdate(
          'UPDATE produto SET quantidade_estoque = quantidade_estoque + ? WHERE id_produto = ?',
          [quantidade, idProduto],
        );
      }
      
      // Atualizar status do pedido
      await txn.update(
        'pedido',
        {
          'status_pedido': 'cancelado',
          'data_finalizacao': DateTime.now().toIso8601String(),
        },
        where: 'id_pedido = ?',
        whereArgs: [idPedido],
      );
      
      // Registrar cancelamento
      await txn.insert('pedido_cancelamento', {
        'id_pedido': idPedido,
        'motivo': motivo,
        'id_usuario_cancelou': idUsuarioCancelou,
        'data_cancelamento': DateTime.now().toIso8601String(),
      });
    });
    
    // 🔥 NOVO: Notificar mudança no estoque
    notificarMudancaEstoque();
      EstoqueAlertaService.instance.verificarEstoque();
  } catch (e) {
    print('Erro ao cancelar pedido: $e');
    rethrow;
  }
}
// Stream controller para notificar mudanças no estoque
final _estoqueStreamController = StreamController<void>.broadcast();
Stream<void> get estoqueStream => _estoqueStreamController.stream;

void notificarMudancaEstoque() {
  _estoqueStreamController.add(null);
}

// 10. Finalizar pedido (mudar status para "finalizado")
Future<void> finalizarPedido(int idPedido, int idTipoPagamento, {
  double? valorPago,
  double? troco,
}) async {
  final db = await instance.database;
  
  await db.update(
    'pedido',
    {
      'status_pedido': 'finalizado',
      'idtipo_pagamento': idTipoPagamento,
      'valor_pago_manual': valorPago,
      'troco': troco,
      'data_finalizacao': DateTime.now().toIso8601String(),
    },
    where: 'id_pedido = ?',
    whereArgs: [idPedido],
  );
}

Future<int?> getIdCategoriaPromocao() async {
  final db = await instance.database;
  final result = await db.query(
    'categoria',
    columns: ['id_categoria'],
    where: 'nome_categoria = ?',
    whereArgs: ['Promoções da Semana'],
    limit: 1,
  );
  
  if (result.isNotEmpty) {
    return result.first['id_categoria'] as int?;
  }
  return null;
}

// 11. Buscar tipos de pagamento
Future<List<Map<String, dynamic>>> readTiposPagamento() async {
  final db = await instance.database;
  return await db.query('tipo_pagamento', orderBy: 'idtipo_pagamento ASC');
}

// 12. Criar Produto com ID Específico (para importação ou sincronização)

Future<int> createProdutoComIdEspecifico( Produto produto,
  List<int> idsCategorias,
  List<ProdutoImagem> imagens,
) async {
  final db = await database;
  
  return await db.transaction((txn) async {
    // 1. Inserir produto COM ID específico
    await txn.insert(
      'produto',
      produto.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    final idProduto = produto.id!;
    
    // 2. Inserir categorias
    if (idsCategorias.isNotEmpty) {
      for (final idCategoria in idsCategorias) {
        await txn.insert(
          'produto_categoria',
          {'id_produto': idProduto, 'id_categoria': idCategoria},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    
    // 3. Inserir imagens
    if (imagens.isNotEmpty) {
      if (!imagens.any((img) => img.isPrincipal)) {
        imagens[0] = imagens[0].copyWith(isPrincipal: true);
      }
      
      for (final imagem in imagens) {
        await txn.insert(
          'produto_imagem',
          imagem.copyWith(idProduto: idProduto).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
      EstoqueAlertaService.instance.verificarEstoque();

    return idProduto;
  });
}

// lib/services/base_de_dados.dart

Future<int> createCategoriaComIdEspecifico(
  Categoria categoria,
  List<int> idsProdutos,
) async {
  final db = await database;
  
  return await db.transaction((txn) async {
    // 1. Inserir categoria COM ID específico
    await txn.insert(
      'categoria',
      categoria.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    final idCategoria = categoria.id!;
    
    // 2. Inserir associações produto_categoria
    if (idsProdutos.isNotEmpty) {
      for (final idProduto in idsProdutos) {
        await txn.insert(
          'produto_categoria',
          {
            'id_produto': idProduto,
            'id_categoria': idCategoria,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    
    return idCategoria;
  });
}


  Future<int> getDbVersion() async {
    final db = await instance.database;
    return await db.getVersion();
  }
}
