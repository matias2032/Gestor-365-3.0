// lib/widgets/sync_status_widget.dart

import 'package:flutter/material.dart';
import '../services/supabase_sync_service.dart';
import 'dart:async';

/// Widget que mostra o status de sincronização em tempo real
/// Pode ser usado em qualquer tela do app
class SyncStatusWidget extends StatefulWidget {
  final bool showDetails; // Mostrar detalhes ou apenas ícone
  final bool showPendingOps; // Mostrar operações pendentes
  
  const SyncStatusWidget({
    Key? key,
    this.showDetails = true,
    this.showPendingOps = true,
  }) : super(key: key);

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  final _syncService = SupabaseSyncService.instance;
  
  StreamSubscription? _statusSubscription;
  SyncStatus _currentStatus = SyncStatus.idle;
  
  @override
  void initState() {
    super.initState();
    _setupListener();
  }
  
  void _setupListener() {
    _statusSubscription = _syncService.statusStream.listen((status) {
      setState(() {
        _currentStatus = status;
      });
    });
  }
  
  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (widget.showDetails) {
      return _buildDetailedStatus();
    } else {
      return _buildSimpleIcon();
    }
  }
  
  Widget _buildSimpleIcon() {
    final iconData = _getStatusIcon();
    final color = _getStatusColor();
    
    return GestureDetector(
      onTap: () => _showSyncDialog(context),
      child: Container(
        padding: EdgeInsets.all(8),
        child: Stack(
          children: [
            Icon(iconData, color: color, size: 24),
            if (_syncService.pendingOperations > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '${_syncService.pendingOperations}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailedStatus() {
    final isOnline = _syncService.isOnline;
    final pendingOps = _syncService.pendingOperations;
    final isSyncing = _syncService.isSyncing;
    final lastSync = _syncService.lastSyncTime;
    
    return GestureDetector(
      onTap: () => _showSyncDialog(context),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _getBackgroundColor(),
          border: Border(
            bottom: BorderSide(
              color: Colors.grey.shade300,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Ícone de status
            Icon(
              _getStatusIcon(),
              color: _getStatusColor(),
              size: 20,
            ),
            
            SizedBox(width: 12),
            
            // Informações
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status principal
                  Row(
                    children: [
                      Text(
                        _getStatusText(),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (isSyncing)
                        Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _getStatusColor(),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  
                  SizedBox(height: 2),
                  
                  // Informações secundárias
                  Text(
                    _getSecondaryText(isOnline, pendingOps, lastSync),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            
            // Botão de sync manual
            if (isOnline && !isSyncing)
              IconButton(
                icon: Icon(Icons.sync, size: 20),
                onPressed: () async {
                  await _syncService.syncAll();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sincronização completa'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                tooltip: 'Sincronizar agora',
              ),
          ],
        ),
      ),
    );
  }
  
  IconData _getStatusIcon() {
    if (!_syncService.isOnline) return Icons.cloud_off;
    
    switch (_currentStatus) {
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.success:
        return Icons.cloud_done;
      case SyncStatus.error:
        return Icons.error;
      case SyncStatus.offline:
        return Icons.cloud_off;
      default:
        return Icons.cloud;
    }
  }
  
  Color _getStatusColor() {
    if (!_syncService.isOnline) return Colors.orange;
    
    switch (_currentStatus) {
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.success:
        return Colors.green;
      case SyncStatus.error:
        return Colors.red;
      case SyncStatus.offline:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
  
  Color _getBackgroundColor() {
    if (!_syncService.isOnline) return Colors.orange.shade50;
    
    switch (_currentStatus) {
      case SyncStatus.error:
        return Colors.red.shade50;
      default:
        return Colors.white;
    }
  }
  
  String _getStatusText() {
    if (!_syncService.isOnline) return 'Modo Offline';
    
    switch (_currentStatus) {
      case SyncStatus.syncing:
        return 'Sincronizando...';
      case SyncStatus.success:
        return 'Sincronizado';
      case SyncStatus.error:
        return 'Erro na sincronização';
      case SyncStatus.offline:
        return 'Modo Offline';
      default:
        return 'Online';
    }
  }
  
  String _getSecondaryText(bool isOnline, int pendingOps, DateTime? lastSync) {
    if (!isOnline) {
      if (pendingOps > 0) {
        return '$pendingOps operação${pendingOps > 1 ? 'ões' : ''} aguardando sincronização';
      }
      return 'Sem conexão com a internet';
    }
    
    if (pendingOps > 0) {
      return 'Sincronizando $pendingOps operação${pendingOps > 1 ? 'ões' : ''}...';
    }
    
    if (lastSync != null) {
      return 'Última sincronização: ${_formatTime(lastSync)}';
    }
    
    return 'Pronto para sincronizar';
  }
  
  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s atrás';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m atrás';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h atrás';
    } else {
      return '${diff.inDays}d atrás';
    }
  }
  
  void _showSyncDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => SyncInfoDialog(),
    );
  }
}

// ==========================================
// DIALOG DE INFORMAÇÕES DETALHADAS
// ==========================================

class SyncInfoDialog extends StatelessWidget {
  final _syncService = SupabaseSyncService.instance;
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _syncService.isOnline ? Icons.cloud : Icons.cloud_off,
            color: _syncService.isOnline ? Colors.green : Colors.orange,
          ),
          SizedBox(width: 8),
          Text('Status de Sincronização'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoRow(
              'Conexão',
              _syncService.isOnline ? 'Online' : 'Offline',
              _syncService.isOnline ? Colors.green : Colors.orange,
            ),
            Divider(),
            
            _buildInfoRow(
              'Status',
              _syncService.isSyncing ? 'Sincronizando...' : 'Pronto',
              _syncService.isSyncing ? Colors.blue : Colors.grey,
            ),
            Divider(),
            
            _buildInfoRow(
              'Operações Pendentes',
              '${_syncService.pendingOperations}',
              _syncService.pendingOperations > 0 ? Colors.orange : Colors.green,
            ),
            Divider(),
            
            if (_syncService.lastSyncTime != null) ...[
              _buildInfoRow(
                'Última Sincronização',
                _formatDateTime(_syncService.lastSyncTime!),
                Colors.grey,
              ),
              Divider(),
            ],
            
            SizedBox(height: 16),
            
            // Informações adicionais
            Text(
              'Informações',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 8),
            
            if (!_syncService.isOnline)
              _buildWarningCard(
                'Modo Offline',
                'Suas alterações estão sendo salvas localmente e serão '
                'sincronizadas automaticamente quando a conexão for restaurada.',
                Colors.orange,
              ),
            
            if (_syncService.pendingOperations > 0)
              _buildWarningCard(
                'Operações Pendentes',
                'Existem ${_syncService.pendingOperations} operações aguardando '
                'sincronização. Certifique-se de que a conexão está estável.',
                Colors.blue,
              ),
            
            if (_syncService.isOnline && _syncService.pendingOperations == 0)
              _buildWarningCard(
                'Tudo Sincronizado',
                'Todos os dados estão sincronizados com a nuvem.',
                Colors.green,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Fechar'),
        ),
        if (_syncService.isOnline && !_syncService.isSyncing)
          ElevatedButton.icon(
            onPressed: () async {
              await _syncService.syncAll();
              Navigator.pop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Sincronização iniciada')),
              );
            },
            icon: Icon(Icons.sync, size: 18),
            label: Text('Sincronizar'),
          ),
      ],
    );
  }
  
  Widget _buildInfoRow(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildWarningCard(String title, String message, Color color) {
    return Container(
      margin: EdgeInsets.only(top: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: color, size: 18),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatDateTime(DateTime time) {
    return '${time.day.toString().padLeft(2, '0')}/'
           '${time.month.toString().padLeft(2, '0')}/'
           '${time.year} '
           '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}';
  }
}
