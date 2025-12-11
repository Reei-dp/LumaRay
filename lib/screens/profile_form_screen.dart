import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/vless_profile.dart';
import '../models/vless_types.dart';
import '../notifiers/profile_notifier.dart';

class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, this.profile});

  final VlessProfile? profile;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _uuid;
  late final TextEditingController _flow;
  late final TextEditingController _sni;
  late final TextEditingController _alpn;
  late final TextEditingController _fingerprint;
  late final TextEditingController _path;
  late final TextEditingController _hostHeader;
  late final TextEditingController _remark;
  late final TextEditingController _uriImport;
  String _security = 'none';
  VlessTransport _transport = VlessTransport.tcp;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p?.name ?? '');
    _host = TextEditingController(text: p?.host ?? '');
    _port = TextEditingController(text: p?.port.toString() ?? '');
    _uuid = TextEditingController(text: p?.uuid ?? '');
    _flow = TextEditingController(text: p?.flow ?? '');
    _sni = TextEditingController(text: p?.sni ?? '');
    _alpn = TextEditingController(text: p?.alpn.join(',') ?? '');
    _fingerprint = TextEditingController(text: p?.fingerprint ?? '');
    _path = TextEditingController(text: p?.path ?? '');
    _hostHeader = TextEditingController(text: p?.hostHeader ?? '');
    _remark = TextEditingController(text: p?.remark ?? '');
    _uriImport = TextEditingController();
    _security = p?.security ?? 'none';
    _transport = p?.transport ?? VlessTransport.tcp;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _uuid.dispose();
    _flow.dispose();
    _sni.dispose();
    _alpn.dispose();
    _fingerprint.dispose();
    _path.dispose();
    _hostHeader.dispose();
    _remark.dispose();
    _uriImport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.profile != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Редактировать' : 'Новый конфиг'),
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _uriImport,
                decoration: InputDecoration(
                  labelText: 'Импорт VLESS URI',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: _pasteUri,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _applyUri,
                child: const Text('Заполнить из URI'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Название'),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Введите название'
                    : null,
              ),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _host,
                      decoration: const InputDecoration(labelText: 'Хост'),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Хост обязателен'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _port,
                      decoration: const InputDecoration(labelText: 'Порт'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final value = int.tryParse(v ?? '');
                        if (value == null) return 'Неверный порт';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _uuid,
                decoration: const InputDecoration(labelText: 'UUID'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'UUID обязателен' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _security,
                decoration: const InputDecoration(labelText: 'Безопасность'),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('none')),
                  DropdownMenuItem(value: 'tls', child: Text('tls')),
                  DropdownMenuItem(value: 'reality', child: Text('reality')),
                ],
                onChanged: (v) => setState(() => _security = v ?? 'none'),
              ),
              TextFormField(
                controller: _sni,
                decoration: const InputDecoration(labelText: 'SNI'),
              ),
              TextFormField(
                controller: _alpn,
                decoration: const InputDecoration(labelText: 'ALPN через запятую'),
              ),
              TextFormField(
                controller: _fingerprint,
                decoration: const InputDecoration(labelText: 'Fingerprint'),
              ),
              TextFormField(
                controller: _flow,
                decoration: const InputDecoration(labelText: 'Flow (например xtls-rprx-vision)'),
              ),
              DropdownButtonFormField<VlessTransport>(
                initialValue: _transport,
                decoration: const InputDecoration(labelText: 'Транспорт'),
                items: VlessTransport.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(transportToString(t)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _transport = v);
                },
              ),
              TextFormField(
                controller: _path,
                decoration: const InputDecoration(labelText: 'Path/ServiceName'),
              ),
              TextFormField(
                controller: _hostHeader,
                decoration: const InputDecoration(labelText: 'Host Header'),
              ),
              TextFormField(
                controller: _remark,
                decoration: const InputDecoration(labelText: 'Описание'),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.save),
                label: const Text('Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pasteUri() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    setState(() {
      _uriImport.text = text;
    });
  }

  Future<void> _applyUri() async {
    final raw = _uriImport.text.trim();
    if (raw.isEmpty) return;
    try {
      final profile = VlessProfile.fromUri(raw);
      setState(() {
        _name.text = profile.name;
        _host.text = profile.host;
        _port.text = profile.port.toString();
        _uuid.text = profile.uuid;
        _flow.text = profile.flow ?? '';
        _sni.text = profile.sni ?? '';
        _alpn.text = profile.alpn.join(',');
        _fingerprint.text = profile.fingerprint ?? '';
        _transport = profile.transport;
        _path.text = profile.path ?? '';
        _hostHeader.text = profile.hostHeader ?? '';
        _remark.text = profile.remark ?? '';
        _security = profile.security;
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка URI: $e')));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final alpn = _alpn.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final notifier = context.read<ProfileNotifier>();
    final port = int.tryParse(_port.text) ?? 443;

    if (widget.profile == null) {
      await notifier.createManual(
        name: _name.text.trim(),
        host: _host.text.trim(),
        port: port,
        uuid: _uuid.text.trim(),
        security: _security,
        sni: _sni.text.trim().isEmpty ? null : _sni.text.trim(),
        alpn: alpn,
        fingerprint:
            _fingerprint.text.trim().isEmpty ? null : _fingerprint.text.trim(),
        flow: _flow.text.trim().isEmpty ? null : _flow.text.trim(),
        transport: _transport,
        path: _path.text.trim().isEmpty ? null : _path.text.trim(),
        hostHeader:
            _hostHeader.text.trim().isEmpty ? null : _hostHeader.text.trim(),
        remark: _remark.text.trim().isEmpty ? null : _remark.text.trim(),
      );
    } else {
      final updated = widget.profile!.copyWith(
        name: _name.text.trim(),
        host: _host.text.trim(),
        port: port,
        uuid: _uuid.text.trim(),
        security: _security,
        sni: _sni.text.trim().isEmpty ? null : _sni.text.trim(),
        alpn: alpn,
        fingerprint:
            _fingerprint.text.trim().isEmpty ? null : _fingerprint.text.trim(),
        flow: _flow.text.trim().isEmpty ? null : _flow.text.trim(),
        transport: _transport,
        path: _path.text.trim().isEmpty ? null : _path.text.trim(),
        hostHeader:
            _hostHeader.text.trim().isEmpty ? null : _hostHeader.text.trim(),
        remark: _remark.text.trim().isEmpty ? null : _remark.text.trim(),
      );
      await notifier.addOrUpdate(updated);
    }

    if (mounted) Navigator.of(context).pop();
  }
}

