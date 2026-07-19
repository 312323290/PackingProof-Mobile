import 'package:flutter/material.dart';

import '../models/order_info.dart';

Future<void> showOrderInfoSheet(BuildContext context, OrderInfo info) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '订单信息',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.58,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: info.details.length,
                separatorBuilder: (_, _) => const Divider(height: 20),
                itemBuilder: (BuildContext context, int index) {
                  final detail = info.details[index];
                  final bool warning = detail.label.startsWith('退款');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        detail.label,
                        style: TextStyle(
                          color: warning
                              ? const Color(0xFFC43D32)
                              : const Color(0xFF69716E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        detail.value,
                        style: const TextStyle(fontSize: 15, height: 1.45),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
