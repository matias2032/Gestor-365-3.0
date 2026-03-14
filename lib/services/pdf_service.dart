// lib/services/pdf_service.dart
// Suporte a A4, térmica 58mm e 80mm com layout adaptativo

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:printing/printing.dart';
import '../models/pedido.dart';
import 'package:intl/intl.dart';

/// Formatos de papel suportados
enum PaperFormat { a4, thermal58mm, thermal80mm }

class PdfService {
  static final PdfService instance = PdfService._internal();
  factory PdfService() => instance;
  PdfService._internal();


double _estimarAlturaTotal(Pedido pedido, bool isSmall, bool temCliente) {
  // Altura inicial (Margens superior/inferior)
  double altura = isSmall ? 15.0 : 30.0;

  // Cabeçalho (Título, Pedido #, Data)
  altura += isSmall ? 25.0 : 45.0;

  // Informação do Cliente
  if (temCliente) {
    altura += isSmall ? 15.0 : 35.0;
  }

  // Lista de Itens
  final int totalItens = pedido.itens?.length ?? 0;
  // No layout térmico (isSmall), cada item costuma ocupar 2 linhas
  double alturaPorItem = isSmall ? 12.0 : 18.0; 
  altura += (totalItens * alturaPorItem);

  // Resumo de Pagamento (Total, Tipo, Troco)
  altura += isSmall ? 20.0 : 40.0;

  // Rodapé
  altura += isSmall ? 15.0 : 25.0;

  // Divisores (estimativa baseada em 4 divisores no código)
  altura += 10.0;

  return altura;
}
  // ─────────────────────────────────────────────
  // Mapeamento de PaperFormat → PdfPageFormat
  // ─────────────────────────────────────────────
static PdfPageFormat _pageFormatFor(PaperFormat format, double alturaDinamica) {
  switch (format) {
    case PaperFormat.thermal58mm:
      return PdfPageFormat(
        58 * PdfPageFormat.mm,
        alturaDinamica * PdfPageFormat.mm,
        marginAll: 2 * PdfPageFormat.mm,
      );
    case PaperFormat.thermal80mm:
      return PdfPageFormat(
        80 * PdfPageFormat.mm,
        alturaDinamica * PdfPageFormat.mm,
        marginAll: 4 * PdfPageFormat.mm,
      );
    case PaperFormat.a4:
      return PdfPageFormat.a4;
  }
}

  // ─────────────────────────────────────────────
  // HELPER CENTRAL: constrói o pw.Document
  // Usado por gerarComprovativo, imprimirComprovativo
  // e imprimirSilencioso — fonte única de verdade.
  // ─────────────────────────────────────────────
pw.Document _buildPdfDocument({
  required Pedido pedido,
  required String tipoPagamento,
  required PaperFormat paperFormat, // Recebe o Enum agora
  String? nomeCliente,
  String? telefoneCliente,
}) {
  final bool isSmall = paperFormat != PaperFormat.a4;
  
  // 1. Calcula a altura dinâmica
  final double alturaDinamica = _estimarAlturaTotal(
    pedido, 
    isSmall, 
    (nomeCliente != null || telefoneCliente != null)
  );

  // 2. Gera o formato correto com a altura calculada
  final pageFormat = _pageFormatFor(paperFormat, alturaDinamica);

  final pdf = pw.Document();
  final double margin = isSmall ? 10 : 40;
  final double baseFontSize = isSmall ? 9 : 12;

  final dataFormatada = DateFormat('dd/MM/yyyy HH:mm').format(
    DateTime.parse(pedido.dataFinalizacao ?? pedido.dataPedido),
  );

  pdf.addPage(
  pw.Page(
    pageTheme: pw.PageTheme(
      pageFormat: pageFormat,
      orientation: pw.PageOrientation.portrait,
      margin: pw.EdgeInsets.all(margin),
      clip: true,
    ),
    build: (context) => pw.Column(
        crossAxisAlignment: isSmall
            ? pw.CrossAxisAlignment.center
            : pw.CrossAxisAlignment.start,
        children: [
          _buildHeader(
            pedido: pedido,
            dataFormatada: dataFormatada,
            isSmall: isSmall,
            baseFontSize: baseFontSize,
          ),
          pw.SizedBox(height: isSmall ? 6 : 16),
          _divider(isSmall),
          pw.SizedBox(height: isSmall ? 4 : 12),
          if (nomeCliente != null || telefoneCliente != null) ...[
            _buildClientInfo(
              nome: nomeCliente,
              telefone: telefoneCliente,
              isSmall: isSmall,
              baseFontSize: baseFontSize,
            ),
            pw.SizedBox(height: isSmall ? 4 : 12),
            _divider(isSmall),
            pw.SizedBox(height: isSmall ? 4 : 12),
          ],
          _buildItemsList(
            pedido: pedido,
            isSmall: isSmall,
            baseFontSize: baseFontSize,
          ),
          pw.SizedBox(height: isSmall ? 4 : 12),
          _divider(isSmall),
          pw.SizedBox(height: isSmall ? 4 : 12),
          _buildPaymentSummary(
            pedido: pedido,
            tipoPagamento: tipoPagamento,
            isSmall: isSmall,
            baseFontSize: baseFontSize,
          ),
          pw.SizedBox(height: isSmall ? 4 : 12),
          _divider(isSmall),
          pw.SizedBox(height: isSmall ? 4 : 8),
          _buildFooter(isSmall: isSmall, baseFontSize: baseFontSize),
        ],
      ),
    ),
  );

  return pdf;
}

  // ─────────────────────────────────────────────
  // Gerar e SALVAR em ficheiro (comportamento original)
  // ─────────────────────────────────────────────
Future<File> gerarComprovativo({
    required Pedido pedido,
    required String tipoPagamento,
    String? nomeCliente,
    String? telefoneCliente,
    PaperFormat paperFormat = PaperFormat.a4,
  }) async {
    final pdf = _buildPdfDocument(
      pedido: pedido,
      tipoPagamento: tipoPagamento,
      paperFormat: paperFormat, // Passa o enum diretamente
      nomeCliente: nomeCliente,
      telefoneCliente: telefoneCliente,
    );
    return _savePdf(pdf, pedido.id!);
  }
  // ─────────────────────────────────────────────
  // Imprimir com diálogo nativo (Printing.layoutPdf)
  // ─────────────────────────────────────────────
Future<void> imprimirComprovativo({
    required Pedido pedido,
    required String tipoPagamento,
    String? nomeCliente,
    String? telefoneCliente,
    PaperFormat paperFormat = PaperFormat.thermal80mm,
  }) async {
    // Nota: O buildPdfDocument já calcula a altura interna
    final pdf = _buildPdfDocument(
      pedido: pedido,
      tipoPagamento: tipoPagamento,
      paperFormat: paperFormat,
      nomeCliente: nomeCliente,
      telefoneCliente: telefoneCliente,
    );
    
    final file = await _savePdf(pdf, pedido.id!);
    final bytes = await file.readAsBytes();

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _nomeAutomatico(pedido.id!),
      // Aqui usamos uma altura genérica para o diálogo, 
      // mas os bytes já levam a altura correta.
      format: _pageFormatFor(paperFormat, 200), 
      dynamicLayout: false,
    );
  }

  // ─────────────────────────────────────────────
  // Impressão silenciosa para impressora guardada
  // Fallback automático para diálogo se não houver
  // impressora configurada.
  // ─────────────────────────────────────────────
Future<void> imprimirSilencioso({
  required Pedido pedido,
  required String tipoPagamento,
  required Printer impressora,
  String? nomeCliente,
  String? telefoneCliente,
  PaperFormat paperFormat = PaperFormat.thermal80mm,
}) async {
  // 1️⃣ O cálculo da altura e a criação do PdfPageFormat agora 
  // acontecem dentro do _buildPdfDocument para evitar erros de argumentos.
  final pdf = _buildPdfDocument(
    pedido: pedido,
    tipoPagamento: tipoPagamento,
    paperFormat: paperFormat, // Passamos o enum diretamente
    nomeCliente: nomeCliente,
    telefoneCliente: telefoneCliente,
  );

  // 2️⃣ Salva e obtém os bytes com o MediaBox (altura) já ajustado
  final file = await _savePdf(pdf, pedido.id!);
  final bytes = await file.readAsBytes();

  // 3️⃣ Envia diretamente para a impressora
  await Printing.directPrintPdf(
    printer: impressora,
    onLayout: (_) async => bytes,
    name: _nomeAutomatico(pedido.id!),
    usePrinterSettings: false,
  );
}



/// Nomenclatura automática: FAT-00054-20260312-2159
String _nomeAutomatico(int pedidoId) {
  final agora = DateTime.now();
  final id = pedidoId.toString().padLeft(5, '0');
  final data = DateFormat('yyyyMMdd').format(agora);
  final hora = DateFormat('HHmm').format(agora);
  return 'FAT-$id-$data-$hora';
}

  // ─────────────────────────────────────────────
  // Divisor adaptativo
  // ─────────────────────────────────────────────
  pw.Widget _divider(bool isSmall) {
    if (isSmall) {
      return pw.Text(
        '-' * 32,
        style: const pw.TextStyle(fontSize: 7),
        textAlign: pw.TextAlign.center,
      );
    }
    return pw.Divider(color: PdfColors.grey400, thickness: 1);
  }

  // ─────────────────────────────────────────────
  // Cabeçalho
  // ─────────────────────────────────────────────
  pw.Widget _buildHeader({
    required Pedido pedido,
    required String dataFormatada,
    required bool isSmall,
    required double baseFontSize,
  }) {
    if (isSmall) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            'BAR DIGITAL',
            style: pw.TextStyle(
              fontSize: baseFontSize + 4,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'COMPROVATIVO DE VENDA',
            style: pw.TextStyle(
              fontSize: baseFontSize,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Pedido #${pedido.id}',
            style: pw.TextStyle(fontSize: baseFontSize),
            textAlign: pw.TextAlign.center,
          ),
          pw.Text(
            dataFormatada,
            style: pw.TextStyle(fontSize: baseFontSize - 1),
            textAlign: pw.TextAlign.center,
          ),
        ],
      );
    }

    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.deepOrange, width: 3),
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
                style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'COMPROVATIVO DE VENDA',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
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
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Informações do cliente
  // ─────────────────────────────────────────────
  pw.Widget _buildClientInfo({
    String? nome,
    String? telefone,
    required bool isSmall,
    required double baseFontSize,
  }) {
    if (isSmall) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            'CLIENTE',
            style: pw.TextStyle(fontSize: baseFontSize, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
          ),
          if (nome != null)
            pw.Text(nome, style: pw.TextStyle(fontSize: baseFontSize), textAlign: pw.TextAlign.center),
          if (telefone != null)
            pw.Text(telefone, style: pw.TextStyle(fontSize: baseFontSize), textAlign: pw.TextAlign.center),
        ],
      );
    }

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
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
          ),
          pw.SizedBox(height: 8),
          if (nome != null)
            pw.Text('Nome: $nome', style: const pw.TextStyle(fontSize: 11)),
          if (telefone != null)
            pw.Text('Telefone: $telefone', style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Lista de itens
  // ─────────────────────────────────────────────
  pw.Widget _buildItemsList({
    required Pedido pedido,
    required bool isSmall,
    required double baseFontSize,
  }) {
    final itens = pedido.itens ?? [];

    final List<pw.Widget> widgets = [
      pw.Text(
        'ITENS',
        style: pw.TextStyle(
          fontSize: baseFontSize + (isSmall ? 0 : 2),
          fontWeight: pw.FontWeight.bold,
          color: isSmall ? PdfColors.black : PdfColors.teal,
        ),
        textAlign: isSmall ? pw.TextAlign.center : pw.TextAlign.left,
      ),
      pw.SizedBox(height: isSmall ? 4 : 8),
    ];

    for (final item in itens) {
      final nomeProduto = item.produto?.nome ?? 'Produto';
      final subtotalStr = 'MZN ${item.subtotal.toStringAsFixed(2)}';

      if (isSmall) {
        widgets.add(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                nomeProduto,
                style: pw.TextStyle(fontSize: baseFontSize, fontWeight: pw.FontWeight.bold),
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${item.quantidade}x  MZN ${item.precoUnitario.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: baseFontSize - 1),
                  ),
                  pw.Text(
                    subtotalStr,
                    style: pw.TextStyle(fontSize: baseFontSize - 1, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 3),
            ],
          ),
        );
      } else {
        widgets.add(
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  nomeProduto,
                  style: pw.TextStyle(fontSize: baseFontSize, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Qtd: ${item.quantidade}',
                        style: pw.TextStyle(fontSize: baseFontSize - 1, color: PdfColors.grey700)),
                    pw.Text('Un.: MZN ${item.precoUnitario.toStringAsFixed(2)}',
                        style: pw.TextStyle(fontSize: baseFontSize - 1, color: PdfColors.grey700)),
                    pw.Text('Sub: MZN ${item.subtotal.toStringAsFixed(2)}',
                        style: pw.TextStyle(fontSize: baseFontSize - 1, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    }

    return pw.Column(
      crossAxisAlignment:
          isSmall ? pw.CrossAxisAlignment.stretch : pw.CrossAxisAlignment.start,
      children: widgets,
    );
  }

  // ─────────────────────────────────────────────
  // Resumo de pagamento
  // ─────────────────────────────────────────────
  pw.Widget _buildPaymentSummary({
    required Pedido pedido,
    required String tipoPagamento,
    required bool isSmall,
    required double baseFontSize,
  }) {
    final isDinheiro = tipoPagamento.toLowerCase().contains('dinheiro');
    final totalStr = 'MZN ${pedido.total.toStringAsFixed(2)}';
    final valorPagoStr = 'MZN ${(pedido.valorPagoManual ?? 0.0).toStringAsFixed(2)}';
    final trocoStr = 'MZN ${(pedido.troco ?? 0.0).toStringAsFixed(2)}';

    pw.Widget paymentRow(String label, String value,
        {bool bold = false, PdfColor? color}) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: baseFontSize,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: baseFontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: color)),
        ],
      );
    }

    final rows = <pw.Widget>[
      paymentRow('TOTAL', totalStr, bold: true,
          color: isSmall ? PdfColors.black : PdfColors.teal),
      pw.SizedBox(height: isSmall ? 3 : 8),
      paymentRow('Pagamento:', tipoPagamento),
      if (isDinheiro) ...[
        pw.SizedBox(height: isSmall ? 2 : 6),
        paymentRow('Valor Pago:', valorPagoStr),
        pw.SizedBox(height: isSmall ? 2 : 6),
        paymentRow('Troco:', trocoStr, color: PdfColors.blue),
      ],
    ];

    if (isSmall) {
      return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: rows);
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(children: rows),
    );
  }

  // ─────────────────────────────────────────────
  // Rodapé
  // ─────────────────────────────────────────────
  pw.Widget _buildFooter({required bool isSmall, required double baseFontSize}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'Documento somente para controlo interno.',
          style: pw.TextStyle(
            fontSize: baseFontSize - (isSmall ? 1 : 2),
            fontStyle: pw.FontStyle.italic,
            color: PdfColors.grey700,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: isSmall ? 3 : 6),
        pw.Text(
          'Obrigado pela sua preferência!',
          style: pw.TextStyle(
            fontSize: baseFontSize + (isSmall ? 0 : 2),
            fontWeight: pw.FontWeight.bold,
            color: isSmall ? PdfColors.black : PdfColors.teal,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: isSmall ? 2 : 4),
        pw.Text(
          'Bar Digital © ${DateTime.now().year}',
          style: pw.TextStyle(fontSize: baseFontSize - 1, color: PdfColors.grey600),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // Salvar PDF em disco
  // ─────────────────────────────────────────────
  Future<File> _savePdf(pw.Document pdf, int pedidoId) async {

   final fileName = '${_nomeAutomatico(pedidoId)}.pdf';  // 🔥
    Directory directory;

    try {
      if (Platform.isAndroid) {
        Directory? dir;
        try {
          final downloads = Directory('/storage/emulated/0/Download/');
          if (await downloads.exists()) {
            final testFile = File('${downloads.path}/.write_test');
            await testFile.writeAsString('test');
            await testFile.delete();
            dir = downloads;
          }
        } catch (_) {}

        if (dir == null) {
          try {
            final extDir = await getExternalStorageDirectory();
            if (extDir != null) {
              dir = Directory('${extDir.path}/Downloads');
              if (!await dir.exists()) await dir.create(recursive: true);
            }
          } catch (_) {}
        }

        directory = dir ?? await getApplicationDocumentsDirectory();
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final downloads = await getDownloadsDirectory();
        directory = downloads ?? await getApplicationDocumentsDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      directory = await getApplicationDocumentsDirectory();
    }

    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // ─────────────────────────────────────────────
  // Abrir PDF em leitor externo
  // ─────────────────────────────────────────────
  Future<void> abrirPdf(File file) async {
    final result = await OpenFile.open(file.path);
    switch (result.type) {
      case ResultType.done:
        return;
      case ResultType.noAppToOpen:
        throw Exception(
          'Nenhuma app de leitura de PDF encontrada.\nFicheiro em: ${file.path}',
        );
      case ResultType.fileNotFound:
        throw Exception('Ficheiro não encontrado: ${file.path}');
      case ResultType.permissionDenied:
        throw Exception('Permissão negada ao abrir o ficheiro.');
      case ResultType.error:
        throw Exception('Erro ao abrir o PDF: ${result.message}');
    }
  }

  /// Impressão silenciosa via SumatraPDF — respeita MediaBox 80mm
Future<void> imprimirViaSumatra({
    required Pedido pedido,
    required String tipoPagamento,
    required String impressoraNome,
    String? nomeCliente,
    String? telefoneCliente,
    PaperFormat paperFormat = PaperFormat.thermal80mm,
  }) async {
    final sumatraPath = '${Directory(Platform.resolvedExecutable).parent.path}\\SumatraPDF.exe';

    final pdf = _buildPdfDocument(
      pedido: pedido,
      tipoPagamento: tipoPagamento,
      paperFormat: paperFormat,
      nomeCliente: nomeCliente,
      telefoneCliente: telefoneCliente,
    );
    final file = await _savePdf(pdf, pedido.id!);

    final result = await Process.run(sumatraPath, [
      '-print-to', impressoraNome,
      '-print-settings', 'fit',
      '-silent',
      file.path,
    ]);

    if (result.exitCode != 0) {
      throw Exception('SumatraPDF erro (${result.exitCode}): ${result.stderr}');
    }
  }
}