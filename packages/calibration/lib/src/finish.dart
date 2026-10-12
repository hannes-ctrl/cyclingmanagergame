/// How a race was decided at the finish.
enum FinishKind {
  solo('Solo'),
  duo('Zu zweit'),
  smallGroup('Kleine Gruppe'),
  bunch('Massensprint'),
  timeTrial('Zeitfahren');

  const FinishKind(this.label);
  final String label;

  /// Kinds a road race can end in, in the order they are reported.
  static const road = [solo, duo, smallGroup, bunch];

  /// Size of the winner's group from which a finish counts as a bunch sprint.
  static const bunchFrom = 25;

  /// Classifies a simulated finish.
  ///
  /// @param firstGroup Number of riders in the winner's group.
  /// @returns The kind of finish.
  static FinishKind ofGroup(int firstGroup) => firstGroup <= 1
      ? solo
      : firstGroup == 2
          ? duo
          : firstGroup < bunchFrom
              ? smallGroup
              : bunch;

  /// Reads the "Won how" field of a ProCyclingStats result page, e.g.
  /// "Bunchsprint", "Sprint a deux", "Sprint of 19 riders" or "18.5 km solo".
  ///
  /// @param wonHow The field's text.
  /// @returns The kind of finish, or null if the text is empty or unknown.
  static FinishKind? parse(String? wonHow) {
    final t = (wonHow ?? '').trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t.contains('solo')) return solo;
    if (t.contains('time trial')) return timeTrial;
    if (t.contains('deux')) return duo;
    if (t.contains('bunch') || t.contains('large group')) return bunch;
    if (t.contains('small group')) return smallGroup;
    final n = RegExp(r'sprint of (\d+) riders').firstMatch(t);
    if (n != null) return ofGroup(int.parse(n[1]!));
    return null;
  }

  /// @param wonHow The "Won how" text.
  /// @returns The length of the winning solo in kilometres, or null if the
  ///   race was not won solo or the page gives no distance.
  static double? soloKm(String? wonHow) {
    final m =
        RegExp(r'([\d.]+) km solo').firstMatch((wonHow ?? '').toLowerCase());
    return m == null ? null : double.tryParse(m[1]!);
  }
}
