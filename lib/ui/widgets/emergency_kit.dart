import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildEmergencyKitPdf(
    {required String accountName, required String secretKey}) async {
  final doc = pw.Document();
  final now = DateTime.now();
  final date =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(48),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('SecureVault Emergency Kit',
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('Created $date', style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 28),
        pw.Text('Account', style: const pw.TextStyle(fontSize: 11)),
        pw.Text(accountName,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 20),
        pw.Text('Secret Key', style: const pw.TextStyle(fontSize: 11)),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 1.2),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(secretKey,
              style: pw.TextStyle(
                  font: pw.Font.courierBold(), fontSize: 15)),
        ),
        pw.SizedBox(height: 14),
        pw.Text('Master password: write it here by hand ____________________',
            style: const pw.TextStyle(fontSize: 12)),
        pw.SizedBox(height: 28),
        pw.Text('How to use this kit',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Bullet(
            text:
                'Signing in on a new device needs your master password AND this Secret Key.'),
        pw.Bullet(
            text:
                'The Secret Key is shown only once and is not visible in the app afterwards.'),
        pw.Bullet(
            text:
                'If you lose it, open SecureVault on a device that is already signed in and link the new device with a QR code (Link from another device).'),
        pw.Bullet(
            text:
                'Print this page or store it somewhere safe and offline. Anyone with the Secret Key and your password can open your vault.'),
      ],
    ),
  ));
  return doc.save();
}

/// Shows the Secret Key once and requires it to be saved as a PDF (or copied)
/// before continuing.
Future<void> showEmergencyKitDialog(
  BuildContext context, {
  required String accountName,
  required String secretKey,
}) {
  var saved = false;
  String? error;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Save your Emergency Kit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Your Secret Key is needed with your master password on new '
                  'devices. It is shown only once. Download it as a PDF and keep '
                  'it safe. If you lose it, link a new device by QR code from '
                  'one that is signed in.'),
              const SizedBox(height: 14),
              SelectableText(secretKey,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style:
                          TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
              if (saved)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    SizedBox(width: 6),
                    Text('Saved'),
                  ]),
                ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: secretKey));
                setLocal(() => saved = true);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () async {
                try {
                  final bytes = await buildEmergencyKitPdf(
                      accountName: accountName, secretKey: secretKey);
                  final path = await FilePicker.saveFile(
                      fileName: 'SecureVault-Emergency-Kit.pdf',
                      bytes: bytes);
                  if (path != null) {
                    setLocal(() {
                      saved = true;
                      error = null;
                    });
                  }
                } catch (e) {
                  setLocal(() => error = 'Could not save PDF: $e');
                }
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Download PDF'),
            ),
            TextButton(
              onPressed: saved ? () => Navigator.of(ctx).pop() : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    ),
  );
}
