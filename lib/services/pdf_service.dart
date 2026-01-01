// lib/services/pdf_service.dart (CORRIGIDO PARA ANDROID)

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../models/pedido.dart';
import 'package:intl/intl.dart';

class PdfService {
  static final PdfService instance = PdfService._internal();
  factory PdfService() => instance;
  PdfService._internal();

  /// Gera uma fatura em PDF para o pedido
  Future<File> gerarFatura({
    required Pedido pedido,
    required String tipoPagamento,
    String? nomeCliente,
    String? telefoneCliente,
  }) async {
    final pdf = pw.Document();
    
    final dataFormatada = DateFormat('dd/MM/yyyy HH:mm').format(
      DateTime.parse(pedido.dataFinalizacao ?? pedido.dataPedido),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(pedido, dataFormatada),
              pw.SizedBox(height: 24),
              
              if (nomeCliente != null || telefoneCliente != null)
                _buildClientInfo(nomeCliente, telefoneCliente),
              
              pw.SizedBox(height: 24),
              
              _buildItemsTable(pedido),
              
              pw.SizedBox(height: 24),
              
              _buildPaymentSummary(pedido, tipoPagamento),
              
              pw.Spacer(),
              
              _buildFooter(),
            ],
          );
        },
      ),
    );

    return await _savePdf(pdf, pedido.id!);
  }

  pw.Widget _buildHeader(Pedido pedido, String dataFormatada) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: PdfColors.orange,
            width: 3,
          ),
        ),
      ),
      padding: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'BAR DIGITAL',
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.deepOrange,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Sistema de Gestão de Pedidos',
                style: const pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'FATURA',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Pedido #${pedido.id}',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.teal,
                ),
              ),
              pw.Text(
                dataFormatada,
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildClientInfo(String? nome, String? telefone) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CLIENTE',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 8),
          if (nome != null)
            pw.Text(
              'Nome: $nome',
              style: const pw.TextStyle(fontSize: 11),
            ),
          if (telefone != null)
            pw.Text(
              'Telefone: $telefone',
              style: const pw.TextStyle(fontSize: 11),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildItemsTable(Pedido pedido) {
    final itens = pedido.itens ?? [];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColors.teal,
          ),
          children: [
            _buildTableCell('PRODUTO', isHeader: true),
            _buildTableCell('QTD', isHeader: true, alignment: pw.Alignment.center),
            _buildTableCell('PREÇO UN.', isHeader: true, alignment: pw.Alignment.centerRight),
            _buildTableCell('SUBTOTAL', isHeader: true, alignment: pw.Alignment.centerRight),
          ],
        ),
        
        ...itens.map((item) {
          return pw.TableRow(
            children: [
              _buildTableCell(item.produto?.nome ?? 'Produto'),
              _buildTableCell(
                item.quantidade.toString(),
                alignment: pw.Alignment.center,
              ),
              _buildTableCell(
                'MZN ${item.precoUnitario.toStringAsFixed(2)}',
                alignment: pw.Alignment.centerRight,
              ),
              _buildTableCell(
                'MZN ${item.subtotal.toStringAsFixed(2)}',
                alignment: pw.Alignment.centerRight,
              ),
            ],
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    pw.Alignment alignment = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      alignment: alignment,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 11 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
  }

  pw.Widget _buildPaymentSummary(Pedido pedido, String tipoPagamento) {
    final isDinheiroVivo = tipoPagamento.toLowerCase().contains('dinheiro');
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'MZN ${pedido.total.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.teal,
                ),
              ),
            ],
          ),
          
          pw.SizedBox(height: 12),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 12),
          
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Método de Pagamento:',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Text(
                tipoPagamento,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          
          if (isDinheiroVivo) ...[
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Valor Pago:',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.Text(
                  'MZN ${(pedido.valorPagoManual ?? 0.0).toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Troco:',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.Text(
                  'MZN ${(pedido.troco ?? 0.0).toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 8),
        pw.Text(
          'Obrigado pela sua preferência!',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.teal,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Bar Digital © ${DateTime.now().year}',
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey600,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  /// 🔥 CORRIGIDO: Salvar em local mais acessível no Android
  Future<File> _savePdf(pw.Document pdf, int pedidoId) async {
    Directory directory;
    
    // 🔥 CORREÇÃO: Tentar diferentes diretórios dependendo da plataforma
    if (Platform.isAndroid) {
      // Tenta usar Download ou Documents públicos
      try {
        directory = Directory('/storage/emulated/0/Download/');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        }
      } catch (e) {
        directory = await getApplicationDocumentsDirectory();
      }
    } else {
      // iOS e outras plataformas
      directory = await getApplicationDocumentsDirectory();
    }
    
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Fatura_Pedido_${pedidoId}_$timestamp.pdf';
    final file = File('${directory.path}/$fileName');
    
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// 🔥 CORRIGIDO: Método mais robusto para abrir PDF
  Future<void> abrirPdf(File file) async {
    try {
      final result = await OpenFile.open(file.path);
      
      // Verificar resultado
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } catch (e) {
      // Lançar exceção para ser tratada na UI
      throw Exception('Não foi possível abrir o PDF: $e');
    }
  }
}