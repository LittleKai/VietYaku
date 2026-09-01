import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/settings/presentation/donate_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('showDonateDialog hiển thị thông tin ngân hàng và nút sao chép', (
    tester,
  ) async {
    final List<MethodCall> log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          log.add(methodCall);
          return null;
        });

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDonateDialog(context),
              child: const Text('Mở Donate'),
            ),
          ),
        ),
      ),
    );

    // Mở dialog
    await tester.tap(find.text('Mở Donate'));
    await tester.pumpAndSettle();

    // Verify title and bank info
    expect(find.text('Ủng hộ nhà phát triển'), findsOneWidget);
    expect(find.text('Vietcombank (VCB)'), findsOneWidget);
    expect(find.text('0071000718658'), findsOneWidget);
    expect(find.text('NGUYEN ANH DUC'), findsOneWidget);
    expect(find.text('Ung ho VietYaku'), findsOneWidget);
    expect(find.text('Sao chép STK'), findsOneWidget);
    expect(find.text('Tải mã QR về máy'), findsOneWidget);

    // Bấm sao chép STK
    await tester.ensureVisible(find.text('Sao chép STK'));
    await tester.tap(find.text('Sao chép STK'));
    await tester.pump();

    // Verify clipboard call
    final clipboardCalls = log.where(
      (call) => call.method == 'Clipboard.setData',
    );
    expect(clipboardCalls.isNotEmpty, isTrue);
    expect(clipboardCalls.last.arguments['text'], '0071000718658');

    // Đóng dialog
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();

    expect(find.text('Ủng hộ nhà phát triển'), findsNothing);
  });
}
