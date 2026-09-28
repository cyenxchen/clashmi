import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmi/app/clash/clash_http_api.dart';
import 'package:clashmi/i18n/strings.g.dart';
import 'package:clashmi/screens/proxy_board_screen_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late HttpOverrides? overrides;
  late Object providers;
  late int providerStatus;
  late Duration responseDelay;
  late int activeChecks;
  late int maximumActiveChecks;
  Completer<void>? providerGate;
  Completer<void>? providerReached;
  final requests = <String>[];
  final requestUris = <Uri>[];

  setUp(() async {
    overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    requests.clear();
    requestUris.clear();
    providerStatus = 200;
    responseDelay = Duration.zero;
    activeChecks = maximumActiveChecks = 0;
    providerGate = providerReached = null;
    providers = {
      'providers': {
        'TAG / 8': {
          'proxies': [
            {
              'name': 'HK 1',
              'type': 'Shadowsocks',
              'history': [
                {'delay': 80},
              ],
              'extra': {
                'http://www.gstatic.com/generate_204': {
                  'alive': true,
                  'history': [
                    {'delay': 80},
                  ],
                },
              },
            },
            {'name': 'duplicate', 'type': 'Shadowsocks'},
          ],
        },
        'flowercloud': {
          'proxies': [
            {'name': 'HK 2', 'type': 'Trojan'},
            {'name': 'HK 1', 'type': 'Trojan'},
          ],
        },
      },
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ClashHttpApi.getControlPort = () => server.port;
    server.listen((request) async {
      requests.add(request.uri.path);
      requestUris.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/proxies') {
        request.response.write(
          jsonEncode({
            'proxies': {
              'HK': {
                'name': 'HK',
                'type': 'URLTest',
                'now': 'HK 1',
                'all': ['HK 1', 'HK 2'],
                'testUrl': 'http://www.gstatic.com/generate_204',
                'expectedStatus': '204',
              },
              'duplicate': {'name': 'duplicate', 'type': 'Direct'},
            },
          }),
        );
      } else if (request.uri.path == '/providers/proxies') {
        if (providerReached != null && !providerReached!.isCompleted) {
          providerReached!.complete();
        }
        await providerGate?.future;
        request.response.statusCode = providerStatus;
        request.response.write(jsonEncode(providers));
      } else {
        activeChecks++;
        if (activeChecks > maximumActiveChecks) {
          maximumActiveChecks = activeChecks;
        }
        await Future<void>.delayed(responseDelay);
        request.response.write(jsonEncode({'delay': 80}));
        activeChecks--;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    ClashHttpApi.getControlPort = null;
    HttpOverrides.global = overrides;
  });

  test(
    'resolves provider-only group members with top-level precedence',
    () async {
      final result = await ClashHttpApi.getProxies();
      expect(result.error, isNull);
      expect(result.data!.map((node) => node.name), [
        'HK',
        'duplicate',
        'HK 1',
        'HK 2',
      ]);
      expect(
        result.data!.singleWhere((node) => node.name == 'duplicate').type,
        'Direct',
      );
      expect(result.data!.singleWhere((node) => node.name == 'HK').delay, 80);
    },
  );

  test('surfaces provider HTTP errors with usable top-level nodes', () async {
    providerStatus = 503;
    final result = await ClashHttpApi.getProxies();
    expect(result.error?.message, contains('503'));
    expect(result.data!.map((node) => node.name), ['HK', 'duplicate']);
  });

  test(
    'surfaces malformed provider data instead of silently dropping members',
    () async {
      providers = {'providers': []};
      final result = await ClashHttpApi.getProxies();
      expect(result.error, isNotNull);
      expect(result.data, isNotEmpty);
    },
  );

  testWidgets(
    'tests all provider group members without testing or unfixing groups',
    (tester) async {
      final result = await tester.runAsync(ClashHttpApi.getProxies);
      final controller = ProxyScreenProxiesNodeWidgetController(
        onTesting: () {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProxyScreenProxiesNodeWidget(
              nodes: result!.data!,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.runAsync(controller.delayTest);
      expect(
        requests,
        contains('/providers/proxies/TAG%20%2F%208/HK%201/healthcheck'),
      );
      expect(
        requests,
        contains('/providers/proxies/flowercloud/HK%202/healthcheck'),
      );
      expect(requests.where((path) => path.contains('/HK/')), isEmpty);
      expect(requests.where((path) => path.startsWith('/group/')), isEmpty);
      expect(controller.delayTesting(), 0);
      final healthChecks = requestUris.where(
        (uri) => uri.path.endsWith('/healthcheck'),
      );
      expect(healthChecks, hasLength(2));
      for (final uri in healthChecks) {
        expect(
          uri.queryParameters['url'],
          'http://www.gstatic.com/generate_204',
        );
        expect(uri.queryParameters['expected'], '204');
      }
    },
  );

  test('delay test honors its configured timeout beyond one second', () async {
    responseDelay = const Duration(milliseconds: 1200);
    final result = await ClashHttpApi.getDelay(
      'HK 1',
      timeout: const Duration(seconds: 2),
    );
    expect(result.error, isNull);
    expect(result.data, 80);
  });

  test('group delay reflects the health history for its own URL', () {
    final proxies = ClashProxies()
      ..fromJson({
        'proxies': {
          'HK': {
            'name': 'HK',
            'type': 'URLTest',
            'now': 'HK 1',
            'all': ['HK 1'],
            'testUrl': 'http://health.test',
          },
          'HK 1': {
            'name': 'HK 1',
            'type': 'Shadowsocks',
            'history': [
              {'delay': 10},
            ],
            'extra': {
              'http://health.test': {
                'alive': true,
                'history': [
                  {'delay': 90},
                ],
              },
            },
          },
        },
      });
    expect(proxies.proxies.first.delay, 90);
  });

  test('group never borrows a successful history from a different URL', () {
    final proxies = ClashProxies()
      ..fromJson({
        'proxies': {
          'HK': {
            'name': 'HK',
            'type': 'URLTest',
            'now': 'HK 1',
            'all': ['HK 1'],
            'testUrl': 'http://health.test',
          },
          'HK 1': {
            'name': 'HK 1',
            'type': 'Shadowsocks',
            'history': [
              {'delay': 10},
            ],
          },
        },
      });
    expect(proxies.proxies.first.delay, isNull);
  });

  testWidgets('delay checks use at most four concurrent requests', (
    tester,
  ) async {
    responseDelay = const Duration(milliseconds: 20);
    final nodes = List.generate(
      8,
      (i) =>
          ClashProxiesNode()
            ..fromJson({'name': 'node$i', 'type': 'Shadowsocks'}),
    );
    nodes.add(
      ClashProxiesNode()..fromJson({
        'name': 'many',
        'type': 'URLTest',
        'all': nodes.map((node) => node.name).toList(),
      }),
    );
    final controller = ProxyScreenProxiesNodeWidgetController(onTesting: () {});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProxyScreenProxiesNodeWidget(
            nodes: nodes,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.runAsync(controller.delayTest);
    expect(maximumActiveChecks, 4);
    expect(requests.where((path) => path.endsWith('/delay')), hasLength(8));
    expect(controller.delayTesting(), 0);
  });

  testWidgets('cannot select while a refresh can overwrite the selected node', (
    tester,
  ) async {
    final result = await tester.runAsync(ClashHttpApi.getProxies);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: ProxyScreenProxiesNodeWidget(
              nodes: result!.data!,
              controller: null,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      providerGate = Completer<void>();
      providerReached = Completer<void>();
      tester
          .widget<ListTile>(
            find.ancestor(of: find.text('HK'), matching: find.byType(ListTile)),
          )
          .onTap!();
      await providerReached!.future.timeout(const Duration(seconds: 3));
    });
    await tester.pump();
    final member = tester.widget<ListTile>(
      find.ancestor(of: find.text('1 HK 1'), matching: find.byType(ListTile)),
    );
    final onTap = member.onTap;
    await tester.runAsync(() async {
      providerGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(onTap, isNull);
  });

  testWidgets(
    'shared members keep each group health URL and avoid duplicate checks',
    (tester) async {
      final result = await tester.runAsync(ClashHttpApi.getProxies);
      result!.data!.addAll([
        ClashProxiesNode()..fromJson({
          'name': 'Alt',
          'type': 'URLTest',
          'all': ['HK 1'],
          'testUrl': 'https://example.test/health',
          'expectedStatus': '200-299',
        }),
        ClashProxiesNode()..fromJson({
          'name': 'Parent',
          'type': 'Selector',
          'all': ['HK', 'Alt'],
        }),
      ]);
      final controller = ProxyScreenProxiesNodeWidgetController(
        onTesting: () {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProxyScreenProxiesNodeWidget(
              nodes: result.data!,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.runAsync(controller.delayTest);
      final checks = requestUris
          .where((uri) => uri.path.endsWith('/healthcheck'))
          .toList();
      expect(checks, hasLength(3));
      final groupChecks = requestUris.where(
        (uri) => uri.path.endsWith('/delay'),
      );
      expect(
        groupChecks.map((uri) => uri.path),
        containsAll(['/proxies/HK/delay', '/proxies/Alt/delay']),
      );
      expect(requests.where((path) => path.startsWith('/group/')), isEmpty);
      expect(
        checks.where(
          (uri) =>
              uri.queryParameters['url'] ==
              'http://www.gstatic.com/generate_204',
        ),
        hasLength(2),
      );
      expect(
        checks.where(
          (uri) =>
              uri.queryParameters['url'] == 'https://example.test/health' &&
              uri.queryParameters['expected'] == '200-299',
        ),
        hasLength(1),
      );
    },
  );
}
