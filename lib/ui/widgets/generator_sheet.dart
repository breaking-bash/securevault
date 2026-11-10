import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/password_generator.dart';
import '../../state/vault_state.dart';

/// A reusable password-generator panel. If [onUse] is provided a "Use password"
/// button is shown (for filling an entry field); otherwise just copy is offered.
class GeneratorPanel extends StatefulWidget {
  final void Function(String password)? onUse;
  const GeneratorPanel({super.key, this.onUse});

  @override
  State<GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends State<GeneratorPanel> {
  final _gen = PasswordGenerator.instance;
  final _opts = PasswordOptions();
  late String _password;

  @override
  void initState() {
    super.initState();
    _password = _gen.generate(_opts);
  }

  void _regen() => setState(() => _password = _gen.generate(_opts));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strength = _gen.strength(_password);
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Password generator',
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SelectableText(
                  _password,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 18, letterSpacing: 1),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: (strength + 1) / 5,
                  minHeight: 5,
                  backgroundColor: Colors.grey.withValues(alpha: 0.3),
                  color: [
                    Colors.red,
                    Colors.deepOrange,
                    Colors.orange,
                    Colors.lightGreen,
                    Colors.green
                  ][strength],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _regen,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Regenerate'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    context
                        .read<VaultState>()
                        .copyToClipboard(_password, sensitive: true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password copied')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Length: ${_opts.length}'),
              Expanded(
                child: Slider(
                  value: _opts.length.toDouble(),
                  min: 6,
                  max: 64,
                  divisions: 58,
                  label: '${_opts.length}',
                  onChanged: (v) => setState(() {
                    _opts.length = v.round();
                    _password = _gen.generate(_opts);
                  }),
                ),
              ),
            ],
          ),
          _toggle('Uppercase (A-Z)', _opts.upper,
              (v) => setState(() => _opts.upper = v)),
          _toggle('Lowercase (a-z)', _opts.lower,
              (v) => setState(() => _opts.lower = v)),
          _toggle('Digits (0-9)', _opts.digits,
              (v) => setState(() => _opts.digits = v)),
          _toggle('Symbols (!@#…)', _opts.symbols,
              (v) => setState(() => _opts.symbols = v)),
          _toggle('Exclude ambiguous (O/0, l/1…)', _opts.excludeAmbiguous,
              (v) => setState(() => _opts.excludeAmbiguous = v)),
          if (widget.onUse != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                widget.onUse!(_password);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.check),
              label: const Text('Use this password'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      contentPadding: EdgeInsets.zero,
      onChanged: (v) {
        onChanged(v);
        setState(() => _password = _gen.generate(_opts));
      },
    );
  }
}

/// Show the generator as a modal bottom sheet. Returns via [onUse] callback.
Future<void> showGeneratorSheet(BuildContext context,
    {void Function(String)? onUse}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GeneratorPanel(onUse: onUse),
  );
}
