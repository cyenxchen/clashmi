import 'package:clashmi/app/clash/clash_http_api.dart';
import 'package:clashmi/i18n/strings.g.dart';
import 'package:clashmi/screens/proxy_board_screen_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ClashProxiesNode group(String name, {List<String> all = const []}) =>
    ClashProxiesNode()..fromJson({'name': name, 'type': 'URLTest', 'all': all});

Widget board(List<ClashProxiesNode> nodes) => TranslationProvider(
  child: MaterialApp(
    home: Scaffold(
      body: ProxyScreenProxiesNodeWidget(nodes: nodes, controller: null),
    ),
  ),
);

void main() {
  testWidgets('uses refreshed group data after parent rebuild', (tester) async {
    await tester.pumpWidget(board([group('old')]));
    expect(find.text('old'), findsOneWidget);
    await tester.pumpWidget(board([group('HK')]));
    expect(find.text('HK'), findsOneWidget);
    expect(find.text('old'), findsNothing);
  });

  testWidgets('empty group sheet has a visible empty state', (tester) async {
    await tester.pumpWidget(board([group('HK')]));
    await tester.tap(find.text('HK'));
    await tester.pumpAndSettle();
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets(
    'sheet shows group health failure even with positive general delay',
    (tester) async {
      final hk = group('HK', all: ['HK 1'])
        ..fromJson({
          'name': 'HK',
          'type': 'URLTest',
          'all': ['HK 1'],
          'testUrl': 'http://health.test',
        });
      final node = ClashProxiesNode()
        ..fromJson({
          'name': 'HK 1',
          'type': 'Shadowsocks',
          'history': [
            {'delay': 10},
          ],
          'extra': {
            'http://health.test': {
              'alive': false,
              'history': [
                {'delay': 0},
              ],
            },
          },
        });
      await tester.pumpWidget(board([hk, node]));
      await tester.tap(find.text('HK'));
      await tester.pumpAndSettle();
      expect(find.text('Failed'), findsOneWidget);
      expect(find.textContaining('(10 ms)'), findsNothing);
    },
  );
}
