import 'package:clashmi/i18n/fork_network_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ForkNetworkLocationScreen extends StatefulWidget {
  const ForkNetworkLocationScreen({super.key});
  @override
  State<ForkNetworkLocationScreen> createState() => _ForkNetworkLocationState();
}

class _ForkNetworkLocationState extends State<ForkNetworkLocationScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('clashmi_vpn_service');
  bool _foreground = false;
  bool _background = false;
  bool _busy = true;
  bool _failed = false;
  bool _foregroundDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _invoke('networkLocationStatus');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _invoke('networkLocationStatus');
  }

  Future<void> _invoke(String method) async {
    if (mounted) {
      setState(() {
        _busy = true;
        _failed = false;
      });
    }
    try {
      final status = await _channel.invokeMapMethod<String, bool>(method);
      if (mounted) {
        setState(() {
          _foreground = status?['foreground'] ?? false;
          _background = status?['background'] ?? false;
          if (method == 'requestNetworkLocationForeground') {
            _foregroundDenied = !_foreground;
          }
          if (_foreground) _foregroundDenied = false;
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = ForkNetworkLocationText.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(text.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(text.description),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(text.foreground),
            subtitle: Text(_foreground ? text.granted : text.denied),
            leading: Icon(
              _foreground
                  ? Icons.check_circle_outline
                  : Icons.location_off_outlined,
            ),
          ),
          FilledButton(
            key: const Key('network-foreground'),
            onPressed: _busy || _foreground
                ? null
                : () => _invoke('requestNetworkLocationForeground'),
            child: Text(text.requestForeground),
          ),
          if (_foregroundDenied) Text(text.foregroundDeniedHelp),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(text.background),
            subtitle: Text(_background ? text.granted : text.denied),
            leading: Icon(
              _background
                  ? Icons.check_circle_outline
                  : Icons.location_off_outlined,
            ),
          ),
          Text(text.backgroundHelp),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('network-background'),
            onPressed: _busy || !_foreground || _background
                ? null
                : () => _invoke('requestNetworkLocationBackground'),
            child: Text(text.requestBackground),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _invoke('openNetworkLocationSettings'),
            child: Text(text.settings),
          ),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_failed)
            Text(
              text.error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
