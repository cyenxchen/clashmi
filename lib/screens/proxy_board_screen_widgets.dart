import 'dart:io';

import 'package:clashmi/i18n/strings.g.dart';

import 'package:clashmi/app/clash/clash_config.dart';
import 'package:clashmi/app/clash/clash_http_api.dart';
import 'package:clashmi/app/modules/setting_manager.dart';
import 'package:clashmi/screens/dialog_utils.dart';
import 'package:clashmi/screens/theme_define.dart';
import 'package:clashmi/screens/widgets/sheet.dart';
import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:flutter/material.dart';

class ProxyScreenProxiesNodeWidgetController {
  void Function()? onTesting;

  Future<void> Function()? delayTestFun;
  int Function()? delayTestingFun;
  Future<void> Function()? refreshFun;
  bool Function()? refreshingFun;
  bool get refreshing => refreshingFun?.call() ?? false;
  ProxyScreenProxiesNodeWidgetController({required this.onTesting});
  Future<void> delayTest() async {
    if (delayTestFun != null) {
      return delayTestFun!.call();
    }
  }

  int delayTesting() {
    if (delayTestingFun != null) {
      return delayTestingFun!.call();
    }
    return 0;
  }
}

class ProxyScreenProxiesNodeWidget extends StatefulWidget {
  const ProxyScreenProxiesNodeWidget({
    super.key,
    required this.nodes,
    required this.controller,
    this.errorMessage,
  });
  final List<ClashProxiesNode> nodes;
  final ProxyScreenProxiesNodeWidgetController? controller;
  final String? errorMessage;
  @override
  State<ProxyScreenProxiesNodeWidget> createState() =>
      _ProxyScreenProxiesNodeWidget();
}

class _ProxyScreenProxiesNodeWidget
    extends State<ProxyScreenProxiesNodeWidget> {
  late List<ClashProxiesNode> _nodes;
  final Set<(String?, String, String, String)> _nodesTesting = {};
  final Set<(String?, String, String, String)> _failedTests = {};
  final ValueNotifier<int> _sheetRevision = ValueNotifier(0);
  bool _refreshing = false;
  String? _loadError;

  @override
  void initState() {
    widget.controller?.delayTestFun = () async {
      return delayTest();
    };
    widget.controller?.delayTestingFun = () {
      return _nodesTesting.length;
    };
    widget.controller?.refreshFun = _refreshNodes;
    widget.controller?.refreshingFun = () => _refreshing;
    _nodes = widget.nodes.toList();
    _loadError = widget.errorMessage;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant ProxyScreenProxiesNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.nodes, oldWidget.nodes)) {
      _nodes = widget.nodes.toList();
      _failedTests.clear();
      _loadError = widget.errorMessage;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.delayTestFun = null;
      oldWidget.controller?.delayTestingFun = null;
      oldWidget.controller?.refreshFun = null;
      oldWidget.controller?.refreshingFun = null;
      widget.controller?.delayTestFun = () => delayTest();
      widget.controller?.delayTestingFun = () => _nodesTesting.length;
      widget.controller?.refreshFun = _refreshNodes;
      widget.controller?.refreshingFun = () => _refreshing;
    }
  }

  @override
  void dispose() {
    widget.controller?.delayTestFun = null;
    widget.controller?.delayTestingFun = null;
    widget.controller?.refreshFun = null;
    widget.controller?.refreshingFun = null;
    _sheetRevision.dispose();
    super.dispose();
  }

  void _notify() {
    if (!mounted) return;
    setState(() {});
    _sheetRevision.value++;
    widget.controller?.onTesting?.call();
  }

  Future<void> _refreshNodes() async {
    if (_refreshing || _nodesTesting.isNotEmpty) return;
    _refreshing = true;
    _notify();
    try {
      final result = await ClashHttpApi.getProxies();
      if (!mounted) return;
      if (result.data != null) {
        _nodes = result.data!;
        if (result.error == null) _failedTests.clear();
      }
      _loadError = result.error?.message;
    } catch (error) {
      if (mounted) _loadError = error.toString();
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  @override
  Widget build(BuildContext context) {
    Size windowSize = MediaQuery.of(context).size;
    double iconSize = 20;
    var widgets = [];
    for (var node in _nodes) {
      if (node.type != ClashProtocolType.urltest.name &&
          node.type != ClashProtocolType.selector.name &&
          node.type != ClashProtocolType.fallback.name &&
          node.type != ClashProtocolType.loadBalance.name) {
        continue;
      }
      if (node.hidden) {
        continue;
      }
      final selectedNode = _nodes
          .where((member) => member.name == node.now)
          .firstOrNull;
      final failed = selectedNode?.aliveByUrl[node.testUrl] == false;
      String subtitle = "";
      Color? color;
      if (node.delay != null && node.delay! > 0) {
        subtitle = "(${node.delay} ms)";
        if (node.delay! < 800) {
          color = ThemeDefine.kColorGreenBright;
        } else if (node.delay! < 1500) {
          color = Colors.black;
        } else {
          color = Colors.red;
        }
      }

      widgets.add(
        ListTile(
          title: node.icon.isNotEmpty
              ? Row(
                  children: [
                    FastCachedImage(
                      url: node.icon,
                      width: 16,
                      height: 16,
                      cacheWidth: 64,
                      cacheHeight: 64,
                      loadingBuilder: (context, loadingProgress) {
                        return SizedBox.shrink();
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return SizedBox.shrink();
                      },
                    ),
                    SizedBox(width: 5),
                    Text(
                      node.name,
                      style: TextStyle(
                        fontFamily: Platform.isWindows ? 'Emoji' : null,
                      ),
                    ),
                  ],
                )
              : Text(
                  node.name,
                  style: TextStyle(
                    fontFamily: Platform.isWindows ? 'Emoji' : null,
                  ),
                ),
          subtitle: _nodesTesting.isEmpty
              ? (node.delay == null
                    ? Text(
                        failed
                            ? '${node.type} (${Translations.of(context).NetCheckScreen.failed})'
                            : node.type,
                      )
                    : Row(
                        children: [
                          Text(node.type),
                          SizedBox(width: 5),
                          Text(subtitle, style: TextStyle(color: color)),
                        ],
                      ))
              : Row(
                  children: [
                    Text(node.type),
                    SizedBox(width: 5),
                    SizedBox(
                      height: 16,
                      width: 16,
                      child: RepaintBoundary(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ],
                ),
          trailing: SizedBox(
            width: windowSize.width * 0.4,
            child: Row(
              children: [
                SizedBox(
                  width: windowSize.width * 0.4 - iconSize,
                  child: Text(
                    node.now,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Platform.isWindows ? 'Emoji' : null,
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_right, size: iconSize),
              ],
            ),
          ),
          minVerticalPadding: 10,
          onTap: () {
            showNodeSelect(node);
          },
        ),
      );
    }

    final content = widgets.isEmpty
        ? Center(child: Text(Translations.of(context).meta.none))
        : Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Scrollbar(
                child: ListView.separated(
                  itemBuilder: (_, index) {
                    return widgets[index];
                  },
                  separatorBuilder: (BuildContext context, int index) {
                    return const Divider(height: 1, thickness: 0.3);
                  },
                  itemCount: widgets.length,
                ),
              ),
            ),
          );
    return Column(
      children: [
        if (_refreshing) const LinearProgressIndicator(),
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              Translations.of(context).meta.updateFailed(p: _loadError!),
            ),
          ),
        Expanded(child: content),
      ],
    );
  }

  Future<void> showNodeSelect(ClashProxiesNode selected) async {
    // Load current provider membership and selection whenever the sheet opens.
    final refresh = _refreshNodes();
    await showSheet(
      context: context,
      body: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: ValueListenableBuilder<int>(
          valueListenable: _sheetRevision,
          builder: (context, _, _) {
            final t = Translations.of(context);
            final group = _nodes
                .where((node) => node.name == selected.name)
                .firstOrNull;
            final byName = {for (final node in _nodes) node.name: node};
            final members = <ClashProxiesNode>[];
            final missing = <String>[];
            for (final name in group?.all ?? <String>[]) {
              final node = byName[name];
              if (node == null) {
                missing.add(name);
              } else {
                members.add(node);
              }
            }
            if (SettingManager.getConfig().ui.delayTestSort) {
              members.sort((a, b) {
                final aDelay = a.delayForUrl(group?.testUrl ?? '');
                final bDelay = b.delayForUrl(group?.testUrl ?? '');
                if (aDelay == null) return bDelay == null ? 0 : 1;
                if (bDelay == null) return -1;
                return aDelay.compareTo(bDelay);
              });
            }
            return Column(
              children: [
                ListTile(
                  title: Text(selected.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: t.meta.refresh,
                        onPressed: _refreshing || _nodesTesting.isNotEmpty
                            ? null
                            : _refreshNodes,
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: t.meta.latencyTest,
                        onPressed:
                            _refreshing ||
                                _nodesTesting.isNotEmpty ||
                                group == null
                            ? null
                            : () => delayTest(groupName: group.name),
                        icon: const Icon(Icons.bolt_outlined),
                      ),
                    ],
                  ),
                ),
                if (_refreshing) const LinearProgressIndicator(),
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(t.meta.updateFailed(p: _loadError!)),
                  ),
                if (missing.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(t.meta.updateFailed(p: missing.join(', '))),
                  ),
                Expanded(
                  child: members.isEmpty
                      ? Center(child: Text(t.meta.none))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: members.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, thickness: 0.3),
                          itemBuilder: (context, index) {
                            final node = members[index];
                            final testing = _nodesTesting.any(
                              (key) => key.$2 == node.name,
                            );
                            final failed =
                                node.aliveByUrl[group?.testUrl ?? ''] ==
                                    false ||
                                _failedTests.any(
                                  (key) =>
                                      key.$2 == node.name &&
                                      (group?.testUrl.isEmpty != false ||
                                          key.$3 == group!.testUrl),
                                );
                            final delay = node.delayForUrl(
                              group?.testUrl ?? '',
                            );
                            final subtitle = failed
                                ? t.NetCheckScreen.failed
                                : delay == null
                                ? node.type
                                : '${node.type} ($delay ms)';
                            return ListTile(
                              title: Text(
                                '${index + 1} ${node.name}',
                                style: TextStyle(
                                  fontFamily: Platform.isWindows
                                      ? 'Emoji'
                                      : null,
                                ),
                              ),
                              subtitle: Text(subtitle),
                              trailing: testing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(),
                                    )
                                  : null,
                              selected: group?.now == node.name,
                              selectedColor: ThemeDefine.kColorBlue,
                              onTap: _refreshing || _nodesTesting.isNotEmpty
                                  ? null
                                  : () async {
                                      final error =
                                          await ClashHttpApi.setProxiesNode(
                                            selected.name,
                                            node.name,
                                          );
                                      if (!context.mounted) return;
                                      if (error != null) {
                                        DialogUtils.showAlertDialog(
                                          context,
                                          error.message,
                                        );
                                        return;
                                      }
                                      group?.now = node.name;
                                      Navigator.of(context).pop();
                                      _notify();
                                      await _refreshNodes();
                                    },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await refresh;
  }

  Future<void> delayTest({String? groupName}) async {
    if (_refreshing || _nodesTesting.isNotEmpty) return;
    final setting = SettingManager.getConfig();
    final byName = {for (final node in _nodes) node.name: node};
    final targets = <(String?, String, String, String), ClashProxiesNode>{};
    final visited = <(String, String, String)>{};
    void addMembers(ClashProxiesNode node, String url, String expected) {
      if (node.isGroup && node.testUrl.isNotEmpty) {
        url = node.testUrl;
        expected = node.expectedStatus;
      }
      if (!visited.add((node.name, url, expected))) return;
      if (node.isGroup) {
        for (final name in node.all) {
          final member = byName[name];
          if (member != null) {
            addMembers(member, url, expected);
            // A nested group is also a proxy with its own health history in
            // the parent. /proxies/{name}/delay keeps its fixed selection.
            if (member.isGroup) {
              targets[(member.providerName, member.name, url, expected)] =
                  member;
            }
          }
        }
      } else if (!ClashProtocolType.toList().contains(node.type)) {
        targets[(node.providerName, node.name, url, expected)] = node;
      }
    }

    for (final node in _nodes) {
      if (node.isGroup &&
          (groupName == null ? !node.hidden : node.name == groupName)) {
        addMembers(node, setting.delayTestUrl, '');
      }
    }
    if (targets.isEmpty) {
      DialogUtils.showAlertDialog(context, Translations.of(context).meta.none);
      return;
    }
    _nodesTesting.addAll(targets.keys);
    _failedTests.removeAll(targets.keys);
    _notify();
    try {
      Future<void> check(
        MapEntry<(String?, String, String, String), ClashProxiesNode> entry,
      ) async {
        if (!mounted) return;
        final key = entry.key;
        final node = entry.value;
        final result = await ClashHttpApi.getDelay(
          node.name,
          providerName: node.providerName,
          url: key.$3,
          expectedStatus: key.$4,
          timeout: Duration(milliseconds: setting.delayTestTimeout),
        );
        if (!mounted) return;
        node.delay = result.data;
        node.delaysByUrl[key.$3] = result.data;
        if (result.error != null) _failedTests.add(key);
        _nodesTesting.remove(key);
        final proxies = ClashProxies()..proxies = _nodes;
        for (final group in _nodes.where((node) => node.isGroup)) {
          group.delay = proxies.updateGroupDelay(group);
        }
        _notify();
      }

      // Bound parallelism for large providers. Nested groups are tested after
      // their members, using /proxies/{name}/delay to preserve fixed selection.
      final leaves = targets.entries
          .where((entry) => !entry.value.isGroup)
          .toList();
      var next = 0;
      Future<void> worker() async {
        while (mounted && next < leaves.length) {
          await check(leaves[next++]);
        }
      }

      await Future.wait(
        List.generate(leaves.length < 4 ? leaves.length : 4, (_) => worker()),
      );
      for (final entry in targets.entries.where(
        (entry) => entry.value.isGroup,
      )) {
        if (!mounted) return;
        await check(entry);
      }
    } finally {
      _nodesTesting.clear();
      _notify();
    }
    if (mounted) await _refreshNodes();
  }
}
