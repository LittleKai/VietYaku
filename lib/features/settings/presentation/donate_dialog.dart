import 'dart:io' show Directory, File, Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/widgets/app_dialog.dart';

const String _kDonateQrUrl =
    'https://img.vietqr.io/image/VCB-0071000718658-compact.png?accountName=NGUYEN%20ANH%20DUC';
const String _kBankName = 'Vietcombank (VCB)';
const String _kAccountNumber = '0071000718658';
const String _kAccountHolder = 'NGUYEN ANH DUC';
const String _kTransferNote = 'Ung ho VietYaku';

/// Mở hộp thoại quét mã QR ủng hộ nhà phát triển.
Future<void> showDonateDialog(BuildContext context) {
  return showAppDialog(
    context: context,
    icon: Icons.favorite_rounded,
    accentColor: const Color(0xFFE91E63),
    title: 'Ủng hộ nhà phát triển',
    description: 'Quét mã VietQR hoặc chuyển khoản trực tiếp qua ngân hàng',
    width: 500,
    content: const DonateDialogContent(),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('Đóng'),
      ),
    ],
  );
}

class DonateDialogContent extends StatefulWidget {
  const DonateDialogContent({super.key});

  @override
  State<DonateDialogContent> createState() => _DonateDialogContentState();
}

class _DonateDialogContentState extends State<DonateDialogContent> {
  int _retryKey = 0;
  bool _isSaving = false;

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Đã sao chép $label vào bộ nhớ tạm.')),
      );
  }

  Future<void> _saveQrImage() async {
    setState(() => _isSaving = true);
    try {
      final uri = Uri.parse(_kDonateQrUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Mã phản hồi: ${response.statusCode}');
      }
      final bytes = response.bodyBytes;

      final String savedPath;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final location = await getSaveLocation(
          suggestedName: 'vietyaku_donate_qr.png',
          acceptedTypeGroups: const [
            XTypeGroup(label: 'Ảnh PNG', extensions: ['png']),
          ],
        );
        if (location == null) {
          // Người dùng hủy lưu file
          return;
        }
        final file = File(location.path);
        await file.writeAsBytes(bytes);
        savedPath = location.path;
      } else {
        // Android / iOS
        Directory? targetDir;
        try {
          targetDir = await getDownloadsDirectory();
        } catch (_) {}
        targetDir ??= await getApplicationDocumentsDirectory();

        final filePath = p.join(targetDir.path, 'vietyaku_donate_qr.png');
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        savedPath = filePath;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Đã lưu mã QR vào: ${p.basename(savedPath)}'),
            action: SnackBarAction(
              label: 'Mở',
              onPressed: () => OpenFilex.open(savedPath),
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Không thể tải/lưu mã QR: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Nếu bạn thấy VietYaku hữu ích trong công việc và học tập, hãy mời tác giả một ly cà phê để tiếp thêm động lực phát triển nhé! Sự đóng góp của bạn là niềm khích lệ rất lớn cho dự án.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),

        // Khung chứa mã QR
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.8),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                _kDonateQrUrl,
                key: ValueKey('donate_qr_$_retryKey'),
                width: 220,
                height: 220,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  final total = progress.expectedTotalBytes;
                  final loaded = progress.cumulativeBytesLoaded;
                  return SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: total != null ? loaded / total : null,
                        strokeWidth: 2.5,
                        color: const Color(0xFFE91E63),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 220,
                    height: 220,
                    color: Colors.grey.shade100,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 40,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Không thể tải ảnh QR',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _retryKey++),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Thử lại', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Khung thông tin tài khoản ngân hàng
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              _InfoRow(
                label: 'Ngân hàng',
                value: _kBankName,
                icon: Icons.account_balance_outlined,
              ),
              const Divider(height: 14),
              _InfoRow(
                label: 'Số tài khoản',
                value: _kAccountNumber,
                icon: Icons.credit_card_outlined,
                onCopy: () => _copyText(_kAccountNumber, 'số tài khoản'),
              ),
              const Divider(height: 14),
              _InfoRow(
                label: 'Chủ tài khoản',
                value: _kAccountHolder,
                icon: Icons.person_outline_rounded,
              ),
              const Divider(height: 14),
              _InfoRow(
                label: 'Nội dung CK',
                value: _kTransferNote,
                icon: Icons.notes_rounded,
                onCopy: () => _copyText(_kTransferNote, 'lời nhắn chuyển khoản'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Nút tải mã QR & sao chép STK nhanh
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _copyText(_kAccountNumber, 'số tài khoản'),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Sao chép STK'),
            ),
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveQrImage,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE91E63),
                foregroundColor: Colors.white,
              ),
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: const Text('Tải mã QR về máy'),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.onCopy,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
        ),
        if (onCopy != null) ...[
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: 'Sao chép',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onCopy,
          ),
        ],
      ],
    );
  }
}
