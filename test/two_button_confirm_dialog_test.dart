import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/widgets/two_button_confirm_dialog.dart';

void main() {
  testWidgets('确认弹窗始终使用等宽并排双按钮', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TwoButtonConfirmDialog(
            title: '删除录像？',
            message: '这是一段较长的确认说明，用于确认正文滚动时按钮仍保持在底部并排显示。',
            confirmLabel: '确认删除',
            dangerous: true,
          ),
        ),
      ),
    );

    final Rect cancel = tester.getRect(
      find.byKey(const Key('confirm-dialog-cancel')),
    );
    final Rect confirm = tester.getRect(
      find.byKey(const Key('confirm-dialog-confirm')),
    );
    expect(cancel.top, confirm.top);
    expect(cancel.width, closeTo(confirm.width, 0.1));
    expect(cancel.right, lessThan(confirm.left));
    expect(find.byType(FilledButton), findsNWidgets(2));
    expect(find.byType(OutlinedButton), findsNothing);
    final FilledButton cancelButton = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-dialog-cancel')),
    );
    final FilledButton confirmButton = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-dialog-confirm')),
    );
    final ColorScheme colors = Theme.of(
      tester.element(find.byType(TwoButtonConfirmDialog)),
    ).colorScheme;
    expect(
      cancelButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      colors.surfaceContainerHigh,
    );
    expect(
      confirmButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      colors.error,
    );
  });
}
