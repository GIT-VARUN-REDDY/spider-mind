import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/misc.dart';
import '../models/space.dart';
import '../state/app_state.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = s.settings;
    final nh = s.notificationHealth;
    Widget head(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 22, 4, 6), child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.3)));
    final dm = st.digestMinutes;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
        const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        head('Account'),
        Card(child: ListTile(leading: const Icon(Icons.person_outline), title: Text(s.user?.name ?? ''), subtitle: Text(s.user?.email ?? ''), trailing: IconButton(tooltip: 'Edit name', icon: const Icon(Icons.edit_outlined), onPressed: () => _editName(context, s)))),
        head('Appearance'),
        SegmentedButton<ThemeModeSetting>(
          segments: const [ButtonSegment(value: ThemeModeSetting.system, label: Text('System')), ButtonSegment(value: ThemeModeSetting.light, label: Text('Light')), ButtonSegment(value: ThemeModeSetting.dark, label: Text('Dark'))],
          selected: {st.theme},
          onSelectionChanged: (v) => s.updateSettings(st.copyWith(theme: v.first)),
        ),
        head('Reminders'),
        Card(
          child: Column(children: [
            if (!nh.supported) const ListTile(leading: Icon(Icons.info_outline), title: Text('Device reminders need the Android or iOS app'), subtitle: Text('Server reminders still appear in the live feed.')),
            if (nh.supported) ...[
              ListTile(
                leading: Icon(nh.permissionGranted ? Icons.notifications_active : Icons.notifications_off_outlined, color: nh.permissionGranted ? const Color(0xFF2ECC71) : kCrimson),
                title: Text(nh.permissionGranted ? 'Notifications are on' : 'Notifications are off'),
                trailing: nh.permissionGranted ? null : FilledButton(onPressed: s.requestNotificationPermission, child: const Text('Allow')),
              ),
              if (!nh.exactAlarmAllowed) ListTile(leading: const Icon(Icons.alarm_off, color: Colors.amber), title: const Text('Exact timing is off'), subtitle: const Text('Reminders may arrive a few minutes late.'), trailing: TextButton(onPressed: s.openExactAlarmSettings, child: const Text('Fix'))),
              SwitchListTile(secondary: const Icon(Icons.wb_sunny_outlined), title: const Text('Daily digest'), subtitle: Text(st.digestEnabled ? 'Every day at ${_hm(dm)}' : 'Off'), value: st.digestEnabled, onChanged: (v) => s.updateSettings(st.copyWith(digestEnabled: v))),
              if (st.digestEnabled)
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Digest time'),
                  trailing: Text(_hm(dm)),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: dm ~/ 60, minute: dm % 60));
                    if (t != null) s.updateSettings(st.copyWith(digestMinutes: t.hour * 60 + t.minute));
                  },
                ),
              ListTile(leading: const Icon(Icons.send_outlined), title: const Text('Send a test notification'), onTap: s.sendTestNotification),
            ],
          ]),
        ),
        head('Web view'),
        Card(
          child: Column(children: [
            SwitchListTile(title: const Text('Show done threads'), value: st.showDone, onChanged: (v) => s.updateSettings(st.copyWith(showDone: v))),
            SwitchListTile(title: const Text('Reduce motion'), subtitle: const Text('No pulses or flowing particles'), value: st.reduceMotion, onChanged: (v) => s.updateSettings(st.copyWith(reduceMotion: v))),
            SwitchListTile(title: const Text('Low graphics'), subtitle: const Text('No glow. Better for older phones'), value: st.lowGraphics, onChanged: (v) => s.updateSettings(st.copyWith(lowGraphics: v))),
          ]),
        ),
        head('Spaces'),
        Card(child: Column(children: [
          for (final sp in s.spaces) ListTile(leading: CircleAvatar(radius: 8, backgroundColor: sp.color), title: Text(sp.name), trailing: const Icon(Icons.edit_outlined, size: 18), onTap: () => _spaceDialog(context, s, sp)),
          ListTile(leading: const Icon(Icons.add), title: const Text('Add a space'), onTap: () => _spaceDialog(context, s, null)),
        ])),
        head('Data'),
        Card(child: Column(children: [
          ListTile(leading: const Icon(Icons.download_outlined), title: const Text('Copy my data as JSON'), onTap: () { Clipboard.setData(ClipboardData(text: s.exportJson())); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard'))); }),
          ListTile(leading: const Icon(Icons.sync), title: const Text('Sync now'), subtitle: Text(s.lastSyncAt == null ? 'Not synced yet' : 'Last synced ${fmtDue(s.lastSyncAt)}'), onTap: s.refresh),
        ])),
        head('Session'),
        Card(child: Column(children: [
          ListTile(leading: const Icon(Icons.logout), title: const Text('Sign out'), onTap: () async { if (await _confirm(context, 'Sign out?', 'Unsynced changes stay on this device only until you sign back in.') == true) s.signOut(); }),
          ListTile(leading: const Icon(Icons.delete_forever, color: kCrimson), title: const Text('Delete account', style: TextStyle(color: kCrimson)), onTap: () => _deleteAccount(context, s)),
        ])),
      ]),
    );
  }
}

String _hm(int m) {
  final h = (m ~/ 60) % 12 == 0 ? 12 : (m ~/ 60) % 12;
  return '$h:${(m % 60).toString().padLeft(2, '0')} ${m ~/ 60 < 12 ? 'AM' : 'PM'}';
}

Future<bool?> _confirm(BuildContext c, String t, String b) => showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(title: Text(t), content: Text(b), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue'))]));

Future<void> _editName(BuildContext context, AppState s) async {
  final c = TextEditingController(text: s.user?.name);
  final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Your name'), content: TextField(controller: c), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))]));
  if (ok == true && c.text.trim().isNotEmpty) s.updateProfile(name: c.text.trim());
}

Future<void> _deleteAccount(BuildContext context, AppState s) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete account'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('This permanently deletes your account and every thread. Enter your password to confirm.'), const SizedBox(height: 12), TextField(controller: c, obscureText: true, decoration: const InputDecoration(labelText: 'Password'))]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(backgroundColor: kCrimson), onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ),
  );
  if (ok == true && !await s.deleteAccount(c.text) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.authError ?? 'Could not delete the account.')));
  }
}

Future<void> _spaceDialog(BuildContext context, AppState s, Space? sp) async {
  final name = TextEditingController(text: sp?.name ?? '');
  var color = sp?.colorHex ?? kSpacePalette.first;
  String? moveTo;
  await showDialog<void>(
    context: context,
    builder: (dctx) => StatefulBuilder(builder: (dctx, set) {
      final others = s.spaces.where((x) => x.id != sp?.id).toList();
      return AlertDialog(
        title: Text(sp == null ? 'New space' : 'Edit space'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final hex in kSpacePalette)
                InkWell(
                  onTap: () => set(() => color = hex),
                  child: CircleAvatar(radius: 16, backgroundColor: Space(id: '', name: '', colorHex: hex, order: 0).color, child: color == hex ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
                ),
            ]),
            if (sp != null && others.isNotEmpty) ...[
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'To delete: move threads to'),
                items: [for (final o in others) DropdownMenuItem(value: o.id, child: Text(o.name))],
                onChanged: (v) => set(() => moveTo = v),
              ),
            ],
          ]),
        ),
        actions: [
          if (sp != null)
            TextButton(
              onPressed: () async {
                final err = await s.deleteSpace(sp.id, moveTo: moveTo);
                if (!dctx.mounted) return;
                if (err == null) {
                  Navigator.pop(dctx);
                } else {
                  ScaffoldMessenger.of(dctx).showSnackBar(SnackBar(content: Text(err)));
                }
              },
              child: const Text('Delete', style: TextStyle(color: kCrimson)),
            ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              sp == null ? s.createSpace(name.text, color) : s.saveSpace(sp.copyWith(name: name.text.trim(), colorHex: color));
              Navigator.pop(dctx);
            },
            child: const Text('Save'),
          ),
        ],
      );
    }),
  );
}
