import 'package:clashmi/screens/fork_network_location_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('A6 permanent denial points to app settings', (tester) async {
    const channel = MethodChannel('clashmi_vpn_service');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {'foreground': false, 'background': false},
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(
      const MaterialApp(home: ForkNetworkLocationScreen()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('network-foreground')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'If Android no longer shows a permission prompt, enable location in app settings.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'foreground is separate from background and denial keeps entry usable',
    (tester) async {
      const channel = MethodChannel('clashmi_vpn_service');
      var foreground = false;
      var background = false;
      var allow = false;
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'requestNetworkLocationForeground' && allow) {
              foreground = true;
            }
            if (call.method == 'requestNetworkLocationBackground' &&
                foreground) {
              background = true;
            }
            return {'foreground': foreground, 'background': background};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        const MaterialApp(home: ForkNetworkLocationScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Allow foreground location'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('network-background')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('network-foreground')));
      await tester.pumpAndSettle();
      expect(find.byType(ForkNetworkLocationScreen), findsOneWidget);
      expect(
        calls.where((call) => call == 'requestNetworkLocationBackground'),
        isEmpty,
      );
      allow = true;
      await tester.tap(find.byKey(const Key('network-foreground')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('network-background')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('network-background')));
      await tester.pumpAndSettle();
      expect(background, isTrue);
    },
  );
}
