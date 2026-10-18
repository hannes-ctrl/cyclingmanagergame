import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One point of the elevation profile.
class ProfilePoint {
  const ProfilePoint(this.km, this.altitude);

  /// Kilometre from the start of the modelled road (not from the official start).
  final double km;

  /// Altitude in metres.
  final double altitude;
}

/// Kind of a marked point on the route.
enum WaypointType {
  start(1),
  timeTrialStart(2),
  finish(3),
  summitFinish(4),
  sprint(5),
  climb(6),
  feedZone(8),
  teamTimeTrialStart(14),
  unknown(-1);

  const WaypointType(this.code);
  final int code;

  /// Maps the type code of the file to a [WaypointType].
  ///
  /// @param code Type code from the stage file.
  /// @returns The matching type, or `unknown`.
  static WaypointType fromCode(int code) =>
      values.firstWhere((t) => t.code == code, orElse: () => unknown);
}

/// Marked point on the route: start, finish, sprint, mountain prize, feed zone.
class Waypoint {
  const Waypoint(this.km, this.type, this.detail, this.name);

  final double km;
  final WaypointType type;

  /// For [WaypointType.climb] and [WaypointType.summitFinish] the category:
  /// 1 = HC, 2 = first category … 5 = fourth category. For finishes and
  /// sprints a subtype whose meaning has not been worked out yet.
  final int detail;
  final String name;
}

/// Section with a special surface.
class Sector {
  const Sector(
      this.name, this.cobbled, this.difficulty, this.fromKm, this.toKm);

  final String name;

  /// true: cobblestones. false: the file's second sector list, which, judging
  /// by the races it occurs in (Paris–Tours), means unpaved roads.
  final bool cobbled;

  /// Difficulty 1 to 5 (the stars at Paris–Roubaix).
  final int difficulty;
  final double fromKm;
  final double toKm;
}

/// Climb or sector with gradient figures.
class Climb {
  const Climb(this.name, this.kind, this.fromKm, this.toKm, this.avgGradient,
      this.minGradient, this.maxGradient);

  final String name;

  /// 0 for climbs, 3 for cobbled sectors; 1 and 2 are rare and have not been
  /// worked out yet.
  final int kind;
  final double fromKm;
  final double toKm;

  /// Gradients in percent.
  final double avgGradient;
  final double minGradient;
  final double maxGradient;
}

/// Stage file (.cds) from Pro Cycling Manager.
///
/// The profile covers the whole modelled road, including the run-in before
/// the official start and the run-out after the finish. [startKm] and
/// [finishKm] say where the race lies within it.
///
/// After the climbs the file contains further blocks (probably road width
/// and 3D references) that are not read.
class StageFile {
  StageFile._({
    required this.version,
    required this.relief,
    required this.lengthM,
    required this.raceDistanceM,
    required this.elevationGainM,
    required this.maxAltitudeM,
    required this.name,
    required this.profile,
    required this.waypoints,
    required this.sectors,
    required this.climbs,
    required this.detailsDecoded,
  });

  /// Format version from the first byte (seen: 0x69 to 0x89).
  final int version;

  /// Terrain class according to the file. Meaning not confirmed yet
  /// (seen: 1 for flat and hilly, 4 for mountain stages).
  final int relief;

  /// Length of the modelled road.
  final double lengthM;

  /// Race distance from start to finish.
  final double raceDistanceM;
  final double elevationGainM;
  final double maxAltitudeM;

  /// "Start town - finish town".
  final String name;

  final List<ProfilePoint> profile;
  final List<Waypoint> waypoints;
  final List<Sector> sectors;
  final List<Climb> climbs;

  /// false if waypoints, sectors and climbs could not be read (21 of the
  /// 3,328 files of the WorldDB 2026). The profile is still correct.
  final bool detailsDecoded;

  /// Length of the modelled road in kilometres.
  double get lengthKm => lengthM / 1000;

  /// Race distance in kilometres.
  double get raceDistanceKm => raceDistanceM / 1000;

  double? get startKm => _firstOf(const [
        WaypointType.start,
        WaypointType.timeTrialStart,
        WaypointType.teamTimeTrialStart,
      ], last: false);
  double? get finishKm =>
      _firstOf(const [WaypointType.finish, WaypointType.summitFinish],
          last: true);

  double? _firstOf(List<WaypointType> types, {required bool last}) {
    final hits = waypoints.where((w) => types.contains(w.type));
    if (hits.isEmpty) return null;
    return (last ? hits.last : hits.first).km;
  }

  /// Reads and parses a stage file.
  ///
  /// @param path File path.
  /// @returns The parsed stage.
  static StageFile readFile(String path) => parse(File(path).readAsBytesSync());

  // Fixed position of the header fields in every version seen so far.
  static const _magicAt = 0x10;
  static const _reliefAt = 0x27;
  static const _lengthAt = 0x2B;
  static const _raceDistanceAt = 0x2F;
  static const _gainAt = 0x3F;
  static const _maxAltAt = 0x43;
  static const _nameAt = 0x47;

  // Scale of the game world, matched against known points (Galibier, Loze,
  // Briançon, Bourg-d'Oisans): one unit is 10 m of distance or 7.5 m of altitude.
  static const _distanceUnitM = 10.0;
  static const _altitudeUnitM = 7.5;
  static const _unitsPerKm = 1000 / _distanceUnitM;

  /// Parses the bytes of a stage file.
  ///
  /// @param bytes Complete file contents.
  /// @returns The parsed stage; details may be missing, see [detailsDecoded].
  /// @throws FormatException If the file is not a stage file.
  static StageFile parse(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    double f32(int o) => d.getFloat32(o, Endian.little);
    int u32(int o) => d.getUint32(o, Endian.little);

    if (ascii.decode(Uint8List.sublistView(bytes, _magicAt, _magicAt + 11),
            allowInvalid: true) !=
        'CTStageData') {
      throw const FormatException('Not a stage file (CTStageData missing)');
    }
    final nameLen = u32(_nameAt);
    if (nameLen > 200) throw const FormatException('Stage name not found');
    final nameEnd = _nameAt + 4 + nameLen;
    final name = _text(bytes, _nameAt + 4, nameLen);

    // The name is followed by three integers and, depending on the version,
    // five or six floats, then the point count. The profile always starts at x = 0.
    var o = -1;
    for (var k = 3; k <= 9; k++) {
      final c = nameEnd + 12 + k * 4;
      if (c + 20 > bytes.length) break;
      final n = u32(c);
      if (n < 2 || n > 50000 || c + 4 + n * 8 > bytes.length) continue;
      final x1 = f32(c + 12);
      if (f32(c + 4) == 0 && x1 > 0 && x1 <= 100) {
        o = c;
        break;
      }
    }
    if (o < 0) throw const FormatException('Altitude profile not found');

    final n = u32(o);
    final profile = List<ProfilePoint>.generate(n, (i) {
      final p = o + 4 + i * 8;
      return ProfilePoint(
        f32(p) / _unitsPerKm,
        f32(p + 4) * _altitudeUnitM,
      );
    }, growable: false);

    var waypoints = <Waypoint>[];
    var sectors = <Sector>[];
    var climbs = <Climb>[];
    var decoded = true;
    try {
      final r = _Cursor(bytes, d, o + 4 + n * 8);
      waypoints = [
        for (var i = r.count(); i > 0; i--)
          Waypoint(r.f32() / _unitsPerKm, WaypointType.fromCode(r.u32()),
              r.u32(), r.text()),
      ];
      for (final cobbled in const [true, false]) {
        for (var i = r.count(); i > 0; i--) {
          final sectorName = r.text();
          sectors.add(Sector(sectorName, cobbled, r.u32(),
              r.f32() / _unitsPerKm, r.f32() / _unitsPerKm));
        }
      }
      climbs = [
        for (var i = r.count(); i > 0; i--) _climb(r),
      ];
    } on FormatException {
      waypoints = [];
      sectors = [];
      climbs = [];
      decoded = false;
    } on RangeError {
      waypoints = [];
      sectors = [];
      climbs = [];
      decoded = false;
    }

    return StageFile._(
      version: bytes[0],
      relief: u32(_reliefAt),
      lengthM: f32(_lengthAt),
      raceDistanceM: f32(_raceDistanceAt),
      elevationGainM: f32(_gainAt),
      maxAltitudeM: f32(_maxAltAt),
      name: name,
      profile: profile,
      waypoints: waypoints,
      sectors: sectors,
      climbs: climbs,
      detailsDecoded: decoded,
    );
  }

  /// Reads one climb record.
  ///
  /// @param r Cursor positioned at the record.
  /// @returns The climb.
  static Climb _climb(_Cursor r) {
    final kind = r.u32();
    final name = r.text();
    return Climb(name, kind, r.f32() / _unitsPerKm, r.f32() / _unitsPerKm,
        r.f32(), r.f32(), r.f32());
  }

  /// Decodes a text field. Older files store Latin-1, newer ones UTF-8.
  ///
  /// @param bytes File contents.
  /// @param start Offset of the first character.
  /// @param length Length in bytes.
  /// @returns The decoded text.
  static String _text(Uint8List bytes, int start, int length) {
    final raw = Uint8List.sublistView(bytes, start, start + length);
    try {
      return utf8.decode(raw);
    } on FormatException {
      return latin1.decode(raw);
    }
  }
}

/// Sequential little-endian reader for the variable part of the file.
class _Cursor {
  _Cursor(this.bytes, this.data, this.pos);

  final Uint8List bytes;
  final ByteData data;
  int pos;

  /// @returns The next unsigned 32-bit integer.
  int u32() {
    final v = data.getUint32(pos, Endian.little);
    pos += 4;
    return v;
  }

  /// @returns The next 32-bit float.
  double f32() {
    final v = data.getFloat32(pos, Endian.little);
    pos += 4;
    return v;
  }

  /// Reads a list length with a plausibility limit, so that a misplaced read
  /// position shows up at once instead of yielding nonsense.
  ///
  /// @returns The list length.
  /// @throws FormatException If the value is implausibly large.
  int count() {
    final v = u32();
    if (v > 300) throw FormatException('Implausible list length $v', null, pos);
    return v;
  }

  /// @returns The next length-prefixed text.
  String text() {
    final len = u32();
    if (len > 120)
      throw FormatException('Implausible text length $len', null, pos);
    final s = StageFile._text(bytes, pos, len);
    pos += len;
    return s;
  }
}
