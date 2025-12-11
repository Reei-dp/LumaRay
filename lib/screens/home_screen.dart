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
import 'log_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profileNotifier = context.watch<ProfileNotifier>();
    final vpn = context.watch<VpnNotifier>();
    final profiles = profileNotifier.profiles;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LumaRay VLESS'),
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
            tooltip: 'Логи',
            icon: const Icon(Icons.list),
            onPressed: () => _openLogs(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Новый конфиг'),
      ),
      body: profileNotifier.initialized
          ? Column(
              children: [
                _ConnectionCard(
                  vpnStatus: vpn.status,
                  active: profileNotifier.activeProfile,
                  onDisconnect: () => vpn.disconnect(),
                ),
                Expanded(
                  child: profiles.isEmpty
                      ? const Center(child: Text('Конфиги не добавлены'))
                      : ListView.builder(
                          itemCount: profiles.length,
                          itemBuilder: (context, index) {
                            final profile = profiles[index];
                            final isActive =
                                profileNotifier.activeId == profile.id;
                            return Card(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: ListTile(
                                title: Text(profile.name),
                                subtitle:
                                    Text('${profile.host}:${profile.port} • ${transportToString(profile.transport)}'),
                                leading: isActive
                                    ? const Icon(Icons.check_circle, color: Colors.green)
                                    : const Icon(Icons.circle_outlined),
                                trailing: _ProfileActions(
                                  profile: profile,
                                  onConnect: () => _connect(context, profile),
                                  onEdit: () => _openEditor(context, profile: profile),
                                  onDelete: () =>
                                      _confirmDelete(context, profile.id),
                                  onSetActive: () =>
                                      context.read<ProfileNotifier>().setActive(profile.id),
                                ),
                                onTap: () => context
                                    .read<ProfileNotifier>()
                                    .setActive(profile.id),
                              ),
                            );
                          },
                        ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  void _openLogs(BuildContext context) {
    final logPath = context.read<VpnNotifier>().logPath;
    if (logPath == null) {
      _showSnack(context, 'Лог недоступен');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LogScreen(logPath: logPath)),
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

  Future<void> _connect(BuildContext context, VlessProfile profile) async {
    final profileNotifier = context.read<ProfileNotifier>();
    final vpnNotifier = context.read<VpnNotifier>();
    await profileNotifier.setActive(profile.id);
    await vpnNotifier.connect(profile);
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
        title: const Text('Удалить конфиг?'),
        content: const Text('Действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<ProfileNotifier>().delete(id);
            },
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

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.vpnStatus,
    required this.active,
    required this.onDisconnect,
  });

  final VpnStatus vpnStatus;
  final VlessProfile? active;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final statusText = switch (vpnStatus) {
      VpnStatus.connected => 'Подключено',
      VpnStatus.connecting => 'Подключение…',
      VpnStatus.error => 'Ошибка',
      VpnStatus.disconnected => 'Отключено',
    };
    final color = switch (vpnStatus) {
      VpnStatus.connected => Colors.green,
      VpnStatus.connecting => Colors.orange,
      VpnStatus.error => Colors.red,
      VpnStatus.disconnected => Colors.grey,
    };
    return Card(
      margin: const EdgeInsets.all(12),
      child: ListTile(
        leading: Icon(Icons.shield, color: color),
        title: Text(statusText),
        subtitle: Text(active != null
            ? '${active!.name} • ${active!.host}:${active!.port}'
            : 'Нет активного конфига'),
        trailing: vpnStatus == VpnStatus.connected
            ? TextButton(onPressed: onDisconnect, child: const Text('Стоп'))
            : null,
      ),
    );
  }
}

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({
    required this.profile,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
    required this.onSetActive,
  });

  final VlessProfile profile;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetActive;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'connect':
            onConnect();
            break;
          case 'active':
            onSetActive();
            break;
          case 'edit':
            onEdit();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'connect', child: Text('Подключить')),
        const PopupMenuItem(value: 'active', child: Text('Сделать активным')),
        const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
        const PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
  }
}

