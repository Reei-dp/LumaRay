import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.logPath});

  final String logPath;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String _content = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final file = File(widget.logPath);
    if (!await file.exists()) return;
    final text = await file.readAsString();
    if (mounted) {
      setState(() {
        final lines = text.split('\n');
        // Show last 200 lines
        _content = (lines.length > 200 ? lines.sublist(lines.length - 200) : lines)
            .join('\n');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Логи VPN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Text(_content.isEmpty ? 'Лог пуст или не создан' : _content),
      ),
    );
  }
}

