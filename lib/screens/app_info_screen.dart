import 'dart:convert';

import 'package:flutter/material.dart' show showLicensePage;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  static const repo = 'https://github.com/kawaiiepic/Orchid';
  static const api = 'https://api.github.com/repos/kawaiiepic/Orchid';
  static const branch = String.fromEnvironment('ORCHID_BUILD_BRANCH', defaultValue: 'main');
  static const commit = String.fromEnvironment('ORCHID_BUILD_COMMIT');
  static const builtAt = String.fromEnvironment('ORCHID_BUILD_TIME');

  late final Future<PackageInfo> _package;
  late final Future<Object?> _contributors;
  late final Future<Object?> _latest;
  final _client = http.Client();

  @override
  void initState() {
    super.initState();
    _package = PackageInfo.fromPlatform();
    _contributors = _get('$api/contributors');
    _latest = _get('$api/commits/${Uri.encodeComponent(branch)}');
  }

  Future<Object?> _get(String url) async {
    try {
      final response = await _client.get(Uri.parse(url), headers: const {
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {
      // The page still shows local build information when GitHub is offline.
    }
    return null;
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  String _short(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;

  Widget _link(String label, IconData icon, String url) => Button.ghost(
    leading: Icon(icon, size: 17),
    onPressed: () => launchUrl(Uri.parse(url)),
    child: Text(label),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Orchid').large().semiBold(),
      const SizedBox(height: 8),
      FutureBuilder<PackageInfo>(
        future: _package,
        builder: (context, snapshot) {
          final info = snapshot.data;
          return Text(info == null
              ? snapshot.hasError ? 'Version unavailable' : 'Loading version…'
              : 'Version: ${info.version}+${info.buildNumber}');
        },
      ),
      Text('Branch: $branch'),
      Text('Build commit: ${commit.isEmpty ? 'Not recorded' : _short(commit)}'),
      Text('Build time: ${builtAt.isEmpty ? 'Not recorded' : builtAt}'),
      FutureBuilder<Object?>(
        future: _latest,
        builder: (context, snapshot) {
          final latest = snapshot.data;
          final sha = latest is Map ? latest['sha'] : null;
          if (sha is! String) {
            return Text(snapshot.connectionState == ConnectionState.done
                ? 'Could not check latest commit'
                : 'Checking latest commit…').small().muted();
          }
          final label = commit == sha ? 'Up to date (${_short(sha)})'
              : 'Latest on $branch: ${_short(sha)}${commit.isEmpty ? '' : ' — build is behind'}';
          return _link(label, LucideIcons.gitBranch, '$repo/commit/$sha');
        },
      ),
      const SizedBox(height: 16),
      const Text('Contributors').semiBold(),
      FutureBuilder<Object?>(
        future: _contributors,
        builder: (context, snapshot) {
          final entries = snapshot.data;
          if (entries is! List || entries.isEmpty) {
            return Text(snapshot.connectionState == ConnectionState.done
                ? 'Contributors unavailable' : 'Loading contributors…').small().muted();
          }
          return Wrap(
            spacing: 4,
            children: [
              for (final entry in entries.whereType<Map>())
                if (entry['login'] is String)
                  _link('${entry['login']} (${entry['contributions'] ?? 0})',
                    LucideIcons.user,
                    '$repo/commits?author=${Uri.encodeQueryComponent(entry['login'] as String)}'),
            ],
          );
        },
      ),
      const SizedBox(height: 16),
      _link("What's New", LucideIcons.newspaper, '$repo/releases'),
      _link('Report a Problem', LucideIcons.bug, '$repo/issues/new'),
      _link('Community on GitHub', LucideIcons.github, repo),
      _link('Support development', LucideIcons.heart, 'https://github.com/sponsors/kawaiiepic'),
      Button.ghost(
        leading: const Icon(LucideIcons.badgeInfo, size: 17),
        onPressed: () async {
          PackageInfo? info;
          try { info = await _package; } catch (_) {}
          if (!context.mounted) return;
          showLicensePage(
            context: context,
            applicationName: 'Orchid',
            applicationVersion: info == null ? null : '${info.version}+${info.buildNumber}',
          );
        },
        child: const Text('Open Source Licenses'),
      ),
    ],
  );
}
