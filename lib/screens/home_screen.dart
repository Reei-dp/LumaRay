import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vless_profile.dart';
import '../models/vless_types.dart';
import '../notifiers/profile_notifier.dart';
import '../notifiers/vpn_notifier.dart';
import 'profile_form_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profileNotifier = context.watch<ProfileNotifier>();
    final vpn = context.watch<VpnNotifier>();
    final profiles = profileNotifier.profiles;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LumaRay 🚀',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        actions: [
          IconButton(
            tooltip: 'Импорт из буфера',
            icon: const Icon(Icons.content_paste),
            onPressed: () => _importFromClipboard(context),
          ),
          IconButton(
            tooltip: 'Импорт из файла',
            icon: const Icon(Icons.file_open),
            onPressed: () => _importFromFile(context),
          ),
          IconButton(
            tooltip: 'Экспорт/шаринг',
            icon: const Icon(Icons.share),
            onPressed: () => _shareActive(context),
          ),
          IconButton(
            tooltip: 'Новый конфиг',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      body: profileNotifier.initialized
          ? Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                  child: profiles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.vpn_key_rounded,
                                size: 64,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Конфиги не добавлены',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Нажмите кнопку ниже, чтобы добавить',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                    ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: profiles.length,
                          itemBuilder: (context, index) {
                            final profile = profiles[index];
                            final isActive =
                                profileNotifier.activeId == profile.id;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => context
                                    .read<ProfileNotifier>()
                                    .setActive(profile.id),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                                              : Theme.of(context).colorScheme.surface.withOpacity(0.5),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isActive ? Icons.check_circle_rounded : Icons.circle_outlined,
                                          color: isActive
                                              ? Theme.of(context).colorScheme.primary
                                              : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              profile.name,
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    fontFeatures: const [
                                                      FontFeature.enable('liga'),
                                                    ],
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.dns_rounded,
                                                  size: 14,
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${profile.host}:${profile.port}',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                      ),
                                                ),
                                                const SizedBox(width: 12),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    transportToString(profile.transport).toUpperCase(),
                                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                          color: Theme.of(context).colorScheme.primary,
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 10,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      _ProfileActions(
                                        profile: profile,
                                        onEdit: () => _openEditor(context, profile: profile),
                                        onDelete: () =>
                                            _confirmDelete(context, profile.id),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ),
                    _ConnectionBottomBar(
                      vpnStatus: vpn.status,
                      active: profileNotifier.activeProfile,
                      uploadBytes: vpn.uploadBytes,
                      downloadBytes: vpn.downloadBytes,
                      onStart: () => _startVpn(context),
                      onDisconnect: () => vpn.disconnect(),
                    ),
                  ],
                ),
                if (profileNotifier.activeProfile != null &&
                    vpn.status != VpnStatus.connected &&
                    vpn.status != VpnStatus.connecting)
                  Positioned(
                    bottom: 61,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Material(
                        elevation: 8,
                        shape: const CircleBorder(),
                        color: Colors.white,
                        child: InkWell(
                          onTap: () => _startVpn(context),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (vpn.status == VpnStatus.connected)
                  Positioned(
                    bottom: 61,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Material(
                        elevation: 8,
                        shape: const CircleBorder(),
                        color: Colors.white,
                        child: InkWell(
                          onTap: () => vpn.disconnect(),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.stop_rounded,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _importFromClipboard(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      _showSnack(context, 'Буфер обмена пуст');
      return;
    }
    await _importUri(context, text);
  }

  Future<void> _importFromFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'conf', 'json'],
    );
    if (!context.mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    if (path == null) {
      _showSnack(context, 'Не удалось прочитать файл');
      return;
    }
    final content = await File(path).readAsString();
    if (!context.mounted) return;
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      _showSnack(context, 'Файл пуст');
      return;
    }
    var imported = 0;
    for (final line in lines) {
      try {
        await _importUri(context, line, silent: true);
        imported++;
      } catch (_) {}
    }
    if (!context.mounted) return;
    _showSnack(context, 'Импортировано: $imported');
  }

  Future<void> _importUri(BuildContext context, String uri,
      {bool silent = false}) async {
    try {
      final profile =
          await context.read<ProfileNotifier>().importUri(uri.trim());
      if (!context.mounted) return;
      if (!silent) {
        _showSnack(context, 'Импортировано: ${profile.name}');
      }
    } catch (e) {
      if (!context.mounted) return;
      _showSnack(context, 'Ошибка импорта: $e');
    }
  }

  Future<void> _shareActive(BuildContext context) async {
    final active = context.read<ProfileNotifier>().activeProfile;
    if (active == null) {
      _showSnack(context, 'Нет активного конфига');
      return;
    }
    final uri = active.toUri();
    await Share.share(uri, subject: active.name);
  }

  Future<void> _startVpn(BuildContext context) async {
    final profileNotifier = context.read<ProfileNotifier>();
    final vpnNotifier = context.read<VpnNotifier>();
    final activeProfile = profileNotifier.activeProfile;
    if (activeProfile == null) {
      _showSnack(context, 'Выберите конфиг');
      return;
    }
    await vpnNotifier.connect(activeProfile);
  }

  void _openEditor(BuildContext context, {VlessProfile? profile}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileFormScreen(profile: profile),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            const Text('Удалить конфиг?'),
          ],
        ),
        content: const Text('Действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<ProfileNotifier>().delete(id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ConnectionBottomBar extends StatelessWidget {
  const _ConnectionBottomBar({
    required this.vpnStatus,
    required this.active,
    required this.uploadBytes,
    required this.downloadBytes,
    required this.onStart,
    required this.onDisconnect,
  });

  final VpnStatus vpnStatus;
  final VlessProfile? active;
  final int uploadBytes;
  final int downloadBytes;
  final VoidCallback onStart;
  final VoidCallback onDisconnect;

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes Б';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} КБ';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} МБ';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusText = switch (vpnStatus) {
      VpnStatus.connected => 'Подключено',
      VpnStatus.connecting => 'Подключение…',
      VpnStatus.error => 'Ошибка',
      VpnStatus.disconnected => 'Отключено',
    };
    final statusColor = switch (vpnStatus) {
      VpnStatus.connected => const Color(0xFF00D9FF), // Blue like VLESS badge
      VpnStatus.connecting => const Color(0xFFFFB800),
      VpnStatus.error => const Color(0xFFFF4444),
      VpnStatus.disconnected => Colors.white.withOpacity(0.6),
    };
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF000000),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '▲ ${_formatBytes(uploadBytes)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withOpacity(0.9),
                            ),
                      ),
                      Text(
                        '▼ ${_formatBytes(downloadBytes)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withOpacity(0.9),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 80),
                Flexible(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        statusText,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (active != null)
                        Text(
                          '${active!.name}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withOpacity(0.8),
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({
    required this.profile,
    required this.onEdit,
    required this.onDelete,
  });

  final VlessProfile profile;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
        const PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
  }
}

