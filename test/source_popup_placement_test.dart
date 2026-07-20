import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/translation/presentation/source_pane.dart';

void main() {
  test('dòng gần đầu panel đặt popup xuống dưới', () {
    final placement = calculateSourcePopupPlacement(
      panelHeight: 500,
      lineTop: 20,
      lineBottom: 42,
    );

    expect(placement.isBelow, isTrue);
    expect(placement.top, 50);
    expect(placement.bottom, isNull);
  });

  test('dòng gần cuối panel đặt popup lên trên', () {
    final placement = calculateSourcePopupPlacement(
      panelHeight: 500,
      lineTop: 450,
      lineBottom: 472,
    );

    expect(placement.isBelow, isFalse);
    expect(placement.top, isNull);
    expect(placement.bottom, 58);
  });
}
