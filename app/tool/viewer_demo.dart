import 'dart:convert';
import 'dart:io';

import 'package:radmanager/viewer_link.dart';

/// Starts the 3D viewer through the game's link and sends it a race message
/// from a file: `dart run tool/viewer_demo.dart <race.json> [seconds]`.
Future<void> main(List<String> args) async {
  final race =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, Object?>;
  final dataDir = '${Directory.current.parent.path}/data';
  final link = ViewerLink.instance;
  final error = await link.show(dataDir, race);
  if (error != null) {
    stderr.writeln(error);
    exit(1);
  }
  for (var i = 0; i < 60 && !link.connected; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  stdout.writeln(
    link.connected ? 'viewer connected' : 'viewer did not connect',
  );
  for (var i = 0; i < 40 && link.shown == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  stdout.writeln('viewer shows: ${link.shown}');
  await Future<void>.delayed(
    Duration(seconds: args.length > 1 ? int.parse(args[1]) : 8),
  );
  await link.close();
  stdout.writeln('closed');
  exit(0);
}
