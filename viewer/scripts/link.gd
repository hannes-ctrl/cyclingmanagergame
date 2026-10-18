extends Node
## The connection to the game: a WebSocket on the local machine. The game
## sends the stage to show; the viewer answers when it is ready and, later,
## with the instructions of the player for his riders.

signal race_received(message: Dictionary)

const PROTOCOL := 1

var _ws := WebSocketPeer.new()
var _was_open := false


## @param port Port the game listens on.
## @param token Secret the game handed over, so no other program connects.
func connect_to(port: int, token: String) -> void:
	_ws.inbound_buffer_size = 64 * 1024 * 1024
	_ws.outbound_buffer_size = 1024 * 1024
	var err := _ws.connect_to_url("ws://127.0.0.1:%d/viewer?token=%s" % [port, token.uri_encode()])
	if err != OK:
		push_error("Cannot connect to the game: %s" % err)


func _process(_delta: float) -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				send({"type": "hello", "protocol": PROTOCOL})
			while _ws.get_available_packet_count() > 0:
				var text := _ws.get_packet().get_string_from_utf8()
				var m = JSON.parse_string(text)
				if not m is Dictionary:
					continue
				match str(m.get("type", "")):
					"race":
						race_received.emit(m)
					"close":
						get_tree().quit()
		WebSocketPeer.STATE_CLOSED:
			# The game has gone: so does the viewer.
			if _was_open:
				get_tree().quit()


## @param message A message to the game.
func send(message: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(message))
