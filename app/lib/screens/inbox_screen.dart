import 'package:sim/sim.dart';
import 'package:flutter/material.dart';
import 'package:game/game.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

/// @param d A date.
/// @returns `dd.mm.`.
String shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

/// Inbox: the messages on the left, the selected one on the right with a
/// jump to the matching screen.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.state, required this.onOpenRace});
  final AppState state;
  final void Function(int raceId) onOpenRace;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

/// Where the messages of a topic are dealt with: page and button text.
const _areaOf = <String, (String, String)>{
  'Medical': ('squad:shape', 'To form and training'),
  'Training and youth': ('dev', 'To the development team'),
  'Contracts': ('transfers', 'To the transfers'),
  'Licence': ('rankings', 'To the rankings'),
  'Board': ('finance', 'To finances and goals'),
  'Scouting': ('search', 'To the rider search'),
};

/// State of the inbox: the selected message and the topic filter.
class _InboxScreenState extends State<InboxScreen> {
  Message? _selected;
  String? _topic;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.colors;
    final all = s.inbox;
    final topics = <String, int>{};
    for (final m in all) {
      topics[m.topic] = (topics[m.topic] ?? 0) + 1;
    }
    if (!topics.containsKey(_topic)) _topic = null;
    final messages = [
      for (final m in all)
        if (_topic == null || m.topic == _topic) m,
    ];
    // Which topics arrive at all, and whether busy days are summarised.
    final settings = PopupMenuButton<String>(
      tooltip: tr('Inbox settings'),
      icon: const Icon(LucideIcons.settings, size: 18),
      color: c.panel2,
      onSelected: (key) => key == 'digest'
          ? s.setDigest(!s.career.inboxDigest)
          : s.setTopic(key, s.career.mutedTopics.contains(key)),
      itemBuilder: (context) => [
        PopupMenuItem(enabled: false, child: Text(tr('Receive these topics'))),
        for (final key in Message.topics)
          CheckedPopupMenuItem(
            value: key,
            checked: !s.career.mutedTopics.contains(key),
            child: Text(key == 'Scouting' ? key : tr(key)),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: 'digest',
          checked: s.career.inboxDigest,
          child: Text(tr('Summarise three or more messages per topic and day')),
        ),
      ],
    );
    if (messages.isEmpty) {
      return Stack(
        children: [
          Center(
            child: Text(
              s.busy
                  ? tr('The days are running …')
                  : tr(
                      'No messages yet. "Continue" lets the season run until something concerns your team.',
                    ),
              style: const TextStyle(color: TeamColors.muted),
            ),
          ),
          Positioned(top: 12, right: 12, child: settings),
        ],
      );
    }
    final selected = messages.contains(_selected) ? _selected! : messages.first;
    selected.read = true;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(
                      label: tr('All · {0}', [all.length]),
                      selected: _topic == null,
                      colors: c,
                      onTap: () => setState(() => _topic = null),
                    ),
                    for (final e in topics.entries)
                      Pill(
                        label: '${e.key} · ${e.value}',
                        selected: _topic == e.key,
                        colors: c,
                        onTap: () => setState(() => _topic = e.key),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: s.busy ? null : () => s.markAllRead(_topic),
                icon: const Icon(LucideIcons.checkCheck, size: 16),
                label: Text(tr('Mark all read')),
              ),
              TextButton.icon(
                onPressed: s.busy ? null : () => s.deleteRead(_topic),
                icon: const Icon(LucideIcons.trash2, size: 16),
                label: Text(
                  _topic == null
                      ? tr('Delete read messages')
                      : tr('Delete read messages in "{0}"', [_topic]),
                ),
              ),
              TextButton.icon(
                onPressed: s.busy
                    ? null
                    : () async {
                        // Unread messages go too, so ask once.
                        final unread = messages.where((m) => !m.read).length;
                        final sure =
                            unread <= 1 ||
                            await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    content: Text(
                                      tr(
                                        'Delete {0} messages, {1} of them unread?',
                                        [messages.length, unread],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(tr('Cancel')),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(tr('Delete all')),
                                      ),
                                    ],
                                  ),
                                ) ==
                                true;
                        if (sure) s.deleteAll(_topic);
                      },
                icon: const Icon(LucideIcons.trash, size: 16),
                label: Text(
                  _topic == null
                      ? tr('Delete all')
                      : tr('Delete all in "{0}"', [_topic]),
                ),
              ),
              settings,
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 420,
                  child: Panel(
                    colors: c,
                    padding: 0,
                    child: ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final m = messages[i];
                        final current = identical(m, selected);
                        return InkWell(
                          onTap: () => setState(() => _selected = m),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: current ? c.panel2 : null,
                              border: Border(
                                bottom: BorderSide(color: c.line),
                                left: BorderSide(
                                  width: 3,
                                  color: current
                                      ? c.accent
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Label('${m.topic} · ${m.from}'),
                                    const Spacer(),
                                    Text(
                                      shortDate(m.date),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: TeamColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  m.subject,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: m.read
                                        ? FontWeight.w400
                                        : FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Panel(
                    colors: c,
                    padding: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Label(
                                '${selected.topic} · ${selected.from} · '
                                '${shortDate(selected.date)}',
                              ),
                            ),
                            IconButton(
                              tooltip: tr('Delete message'),
                              onPressed: s.busy
                                  ? null
                                  : () => s.deleteMessage(selected),
                              icon: const Icon(LucideIcons.trash2, size: 18),
                              color: TeamColors.muted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          selected.subject,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          selected.body,
                          style: const TextStyle(fontSize: 15, height: 1.5),
                        ),
                        const SizedBox(height: 18),
                        if (selected.raceId != null)
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TeamColors.text,
                              side: BorderSide(color: c.line),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            onPressed: () =>
                                widget.onOpenRace(selected.raceId!),
                            child: Text(tr('To the race')),
                          ),
                        // Every topic has a place where it is dealt with.
                        if (_areaOf[selected.topicKey] case final area?)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: TeamColors.text,
                                side: BorderSide(color: c.line),
                              ),
                              onPressed: () => s.goTo(area.$1),
                              child: Text(tr(area.$2)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
