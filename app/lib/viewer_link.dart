import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sim/sim.dart';

/// The 3D viewer: a separate program (made with Godot) that the game starts
/// and talks to over a WebSocket on this machine. The game sends the stage
/// to show; later the viewer will send the player's instructions back.
class ViewerLink {
  ViewerLink._();

  /// The one link of the game.
  static final instance = ViewerLink._();

  HttpServer? _server;
  WebSocket? _socket;
  Process? _process;
  String _token = '';
  Map<String, Object?>? _waiting;

  /// Title and stage of the race the viewer last reported as shown.
  String? shown;

  /// The texts the viewer shows, in the game's language.
  static Map<String, String> texts() => {
    for (final key in const [
      'Waiting for the game …',
      'Finish',
      '{0} km to go',
      '{0} riders',
      'Director',
      'Motorbike',
      'Helicopter',
      'Rider',
    ])
      key: tr(key),
  };

  /// Looks for the viewer: next to the game in a release, as an export in
  /// the repository, or the Godot editor named in RADMANAGER_GODOT with the
  /// project in the repository.
  ///
  /// @param dataDir The game's data folder.
  /// @returns The command and its arguments, or null if there is none.
  static List<String>? findViewer(String dataDir) {
    final name = Platform.isWindows
        ? 'RadmanagerViewer.exe'
        : Platform.isMacOS
        ? 'RadmanagerViewer.app/Contents/MacOS/RadmanagerViewer'
        : 'RadmanagerViewer.x86_64';
    final os = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'macos'
        : 'linux';
    final roots = <Directory>[];
    for (
      var d = File(Platform.resolvedExecutable).parent, i = 0;
      i < 4;
      d = d.parent, i++
    ) {
      roots.add(d);
    }
    final repo = Directory(dataDir).parent;
    for (final root in [...roots, repo]) {
      for (final path in ['viewer/$name', 'viewer/build/$os/$name']) {
        final f = File('${root.path}/$path');
        if (f.existsSync()) return [f.path];
      }
    }
    final godot = Platform.environment['RADMANAGER_GODOT'];
    final project = File('${repo.path}/viewer/project.godot');
    if (godot != null && File(godot).existsSync() && project.existsSync()) {
      return [godot, '--path', project.parent.path];
    }
    return null;
  }

  /// Shows a stage in the viewer, starting it if it is not running.
  ///
  /// @param dataDir The game's data folder.
  /// @param race A message made by [viewerRace].
  /// @returns null if it is on its way, otherwise why it is not.
  Future<String?> show(String dataDir, Map<String, Object?> race) async {
    final message = {...race, 'texts': texts()};
    final socket = _socket;
    if (socket != null && socket.readyState == WebSocket.open) {
      socket.add(jsonEncode(message));
      return null;
    }
    final command = findViewer(dataDir);
    if (command == null) {
      return tr('The 3D viewer is not installed.');
    }
    _waiting = message;
    await _listen();
    if (_process == null) {
      _token = _newToken();
      try {
        final process = await Process.start(command.first, [
          ...command.skip(1),
          '--',
          '--port=${_server!.port}',
          '--token=$_token',
        ]);
        _process = process;
        // Nobody reads the viewer's output; it must not block on a full pipe.
        process.stdout.drain<void>();
        process.stderr.drain<void>();
        unawaited(
          process.exitCode.then((_) {
            _process = null;
            _socket = null;
          }),
        );
      } on ProcessException catch (e) {
        return tr('The 3D viewer could not be started: {0}', [e.message]);
      }
    }
    return null;
  }

  Future<void> _listen() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      // Only the viewer the game started knows the token.
      if (request.uri.path != '/viewer' ||
          request.uri.queryParameters['token'] != _token ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      _socket = socket;
      socket.listen(
        (data) {
          if (data is! String) return;
          final m = jsonDecode(data);
          if (m is Map && m['type'] == 'shown') {
            shown = '${m['title']} ${m['stage']}'.trim();
          }
          if (m is Map && m['type'] == 'hello') {
            final race = _waiting;
            _waiting = null;
            if (race != null) socket.add(jsonEncode(race));
          }
        },
        onDone: () {
          if (identical(_socket, socket)) _socket = null;
        },
      );
    });
  }

  /// Whether the viewer is connected.
  bool get connected => _socket != null;

  String _newToken() {
    final r = Random.secure();
    return [for (var i = 0; i < 16; i++) r.nextInt(256)]
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Closes the viewer and stops listening, when the game ends.
  Future<void> close() async {
    _socket?.add(jsonEncode({'type': 'close'}));
    await _socket?.close();
    _socket = null;
    _process?.kill();
    _process = null;
    await _server?.close(force: true);
    _server = null;
  }
}
