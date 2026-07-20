import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/shared/widgets/app_dialog.dart';

void main() {
  testWidgets('action đóng dialog dù widget gọi dialog đã bị gỡ', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));

    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    expect(find.text('Nội dung'), findsOneWidget);
    expect(find.text('Mở'), findsNothing);

    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Nội dung'), findsNothing);
  });
}

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _showLauncher = true;

  @override
  Widget build(BuildContext context) {
    if (!_showLauncher) return const SizedBox.shrink();
    return Builder(
      builder: (launcherContext) => FilledButton(
        onPressed: () {
          showAppDialog<void>(
            context: launcherContext,
            icon: Icons.edit,
            title: 'Thử dialog',
            content: const Text('Nội dung'),
            actionsBuilder: (dialogContext) => [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
            ],
          );
          setState(() => _showLauncher = false);
        },
        child: const Text('Mở'),
      ),
    );
  }
}
