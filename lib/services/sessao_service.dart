// lib/services/sessao_service.dart

import '../models/usuario.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessaoService {
  static final SessaoService instance = SessaoService._init();
  SessaoService._init();

  // Propriedades privadas
  Usuario? _usuarioAtual;
  int? _idUsuario;
  String? _nomeUsuario;
  bool _isLogado = false;
  
  // 🔥 Controle de sessão
  static const String _keyUltimaSessao = 'ultima_sessao_timestamp';
  static const String _keyPrimeiroAcesso = 'primeiro_acesso_apos_init';
  
  // 🔥 Timeout de sessão (30 minutos - ajustável)
  static const Duration _timeoutSessao = Duration(minutes: 30);

  // Getters públicos
  Usuario? get usuarioAtual => _usuarioAtual;
  int? get idUsuario => _idUsuario;
  String? get nomeUsuario => _nomeUsuario;
  bool get isLogado => _isLogado;

  // 🔥 Método para marcar que app está ativo
  Future<void> marcarAppAtivo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyUltimaSessao, DateTime.now().millisecondsSinceEpoch);
      print('✅ Timestamp atualizado');
    } catch (e) {
      print('⚠️ Erro ao atualizar timestamp: $e');
    }
  }

  // 🔥 NOVA LÓGICA: Inicializar sessão com detecção de task removal
  Future<void> inicializarSessao() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1️⃣ Verificar se é o primeiro acesso após task removal
      final primeiroAcesso = prefs.getBool(_keyPrimeiroAcesso) ?? true;
      
      if (primeiroAcesso) {
        print('🔄 Primeira inicialização detectada - limpando sessão anterior');
        await limparSessao();
        await prefs.setBool(_keyPrimeiroAcesso, false);
        return;
      }
      
      // 2️⃣ Verificar se existe sessão ativa em memória
      final existeSessaoEmMemoria = _isLogado && _idUsuario != null;
      final idUsuarioSalvo = prefs.getInt('id_usuario');
      
      // 3️⃣ Se não há sessão em memória mas há no SharedPreferences,
      //    significa que o app foi morto pelo sistema (task removal)
      if (!existeSessaoEmMemoria && idUsuarioSalvo != null) {
        print('⚠️ App foi encerrado pelo sistema - sessão invalidada');
        await limparSessao();
        await prefs.setBool(_keyPrimeiroAcesso, true); // Marca para próxima abertura
        return;
      }
      
      // 4️⃣ Verificar timeout da sessão (apenas se já existe sessão em memória)
      if (existeSessaoEmMemoria) {
        final ultimaSessaoTimestamp = prefs.getInt(_keyUltimaSessao);
        
        if (ultimaSessaoTimestamp != null) {
          final ultimaSessao = DateTime.fromMillisecondsSinceEpoch(ultimaSessaoTimestamp);
          final agora = DateTime.now();
          final diferenca = agora.difference(ultimaSessao);
          
          if (diferenca > _timeoutSessao) {
            print('⏱️ Sessão expirada (${diferenca.inMinutes} min) - requer novo login');
            await limparSessao();
            return;
          }
        }
      }
      
      // 5️⃣ Restaurar ou manter sessão
      if (existeSessaoEmMemoria) {
        // Sessão já existe em memória, apenas atualizar timestamp
        await marcarAppAtivo();
        print('✅ Sessão mantida: $_nomeUsuario (ID: $_idUsuario)');
      } else {
        // Tentar restaurar do SharedPreferences (apenas se não foi invalidada acima)
        if (idUsuarioSalvo != null) {
          final nomeUsuarioSalvo = prefs.getString('nome_usuario');
          
          if (nomeUsuarioSalvo != null) {
            _idUsuario = idUsuarioSalvo;
            _nomeUsuario = nomeUsuarioSalvo;
            _isLogado = true;
            
            await marcarAppAtivo();
            print('✅ Sessão restaurada: $_nomeUsuario (ID: $_idUsuario)');
          }
        } else {
          print('ℹ️ Nenhuma sessão encontrada');
          _isLogado = false;
        }
      }
    } catch (e) {
      print('❌ Erro ao inicializar sessão: $e');
      _isLogado = false;
    }
  }

  // Método para definir usuário logado
  Future<void> setUsuario(Usuario usuario) async {
    _usuarioAtual = usuario;
    _idUsuario = usuario.id;
    _nomeUsuario = usuario.nome;
    _isLogado = true;
    
    // Salvar no SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('id_usuario', usuario.id!);
      await prefs.setString('nome_usuario', usuario.nome);
      await prefs.setBool(_keyPrimeiroAcesso, false); // 🔥 Marca sessão estabelecida
      await marcarAppAtivo();
      print('✅ Sessão salva: ${usuario.nome} (ID: ${usuario.id})');
    } catch (e) {
      print('⚠️ Erro ao salvar sessão: $e');
    }
  }

  // Método para limpar sessão (logout)
  Future<void> limparSessao() async {
    _usuarioAtual = null;
    _idUsuario = null;
    _nomeUsuario = null;
    _isLogado = false;
    
    // Limpar SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('id_usuario');
      await prefs.remove('nome_usuario');
      await prefs.remove(_keyUltimaSessao);
      // NÃO remover _keyPrimeiroAcesso aqui - é gerenciado pela inicialização
      print('✅ Sessão limpa');
    } catch (e) {
      print('⚠️ Erro ao limpar sessão: $e');
    }
  }
  
  // 🔥 Método para validar se sessão ainda é válida
  Future<bool> validarSessao() async {
    if (!_isLogado) return false;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final ultimaSessaoTimestamp = prefs.getInt(_keyUltimaSessao);
      
      if (ultimaSessaoTimestamp == null) return false;
      
      final ultimaSessao = DateTime.fromMillisecondsSinceEpoch(ultimaSessaoTimestamp);
      final agora = DateTime.now();
      final diferenca = agora.difference(ultimaSessao);
      
      if (diferenca > _timeoutSessao) {
        print('⏱️ Sessão expirada durante validação');
        await limparSessao();
        return false;
      }
      
      // Atualizar timestamp
      await marcarAppAtivo();
      return true;
    } catch (e) {
      print('❌ Erro ao validar sessão: $e');
      return false;
    }
  }
}