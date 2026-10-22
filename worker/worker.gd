extends SceneTree
## Rules worker for the game server. Runs Godot headless and speaks JSON lines:
##   stdin : {"id": 1, "op": "apply", "profile": {...}, "action": "hire", "args": {...}, "now": 1.7e9, "ctx": {...}}
##   stdout: {"id": 1, "ok": true, "profile": {...}, "result": {...}, "tick": {...}, "snapshot": {...}, "pending": {...}}
## Ops: ping, new_profile, apply, tick, snapshot.
## Start: godot --headless --path <project> --script res://worker/worker.gd
## The server keeps a pool of these processes; all game logic is in Rules.

const MAX_LINE := 64 * 1024 * 1024

func _init() -> void:
	_out({"ready": true, "version": Rules.VERSION})
	while true:
		var line := OS.read_string_from_stdin(MAX_LINE)
		if line == "":
			break  # stdin closed
		line = line.strip_edges()
		if line == "":
			continue
		var req = JSON.parse_string(line)
		if typeof(req) != TYPE_DICTIONARY:
			_out({"ok": false, "error": "bad json"})
			continue
		var res = _handle(req)
		if res == null or typeof(res) != TYPE_DICTIONARY:
			res = {"ok": false, "error": "worker error"}
		res["id"] = req.get("id")
		_out(res)
	quit()

func _out(d: Dictionary) -> void:
	print(JSON.stringify(d))

func _handle(req: Dictionary):
	var now: float = float(req.get("now", Time.get_unix_time_from_system()))
	var ctx: Dictionary = req.get("ctx", {})
	var account := str(ctx.get("account", ""))
	match str(req.get("op", "")):
		"ping":
			return {"ok": true, "pong": true}
		"new_profile":
			var p := Rules.new_profile(int(req.get("seed", randi())), now, str(req.get("name", "Герой")))
			if not ctx.get("real_pool", []).is_empty():
				var r := Rules._rng(p)
				p["board"] = Rules.roll_board(p, r, ctx)
				Rules._save_rng(p, r)
			return _wrap(p, account, now, {}, {"reports": [], "assists": []})
		"tick":
			var p: Dictionary = req["profile"]
			Rules.migrate(p, now)
			var t := Rules.tick(p, now, ctx)
			return _wrap(p, account, now, {}, t)
		"apply":
			var p: Dictionary = req["profile"]
			var action := str(req.get("action", ""))
			var internal: bool = req.get("internal", false)
			if action in Rules.INTERNAL_ACTIONS and not internal:
				return {"ok": false, "error": "action not allowed"}
			if not (action in Rules.LOCAL_ACTIONS or action in Rules.AUTHORITY_ACTIONS or action in Rules.INTERNAL_ACTIONS):
				return {"ok": false, "error": "unknown action"}
			Rules.migrate(p, now)
			var t := Rules.tick(p, now, ctx)
			var result := Rules.apply(p, action, req.get("args", {}), now, ctx)
			return _wrap(p, account, now, result, t)
		"snapshot":
			var p: Dictionary = req["profile"]
			Rules.migrate(p, now)
			return {"ok": true, "snapshot": Rules.public_snapshot(p, account)}
	return {"ok": false, "error": "unknown op"}

func _wrap(p: Dictionary, account: String, now: float, result: Dictionary, t: Dictionary) -> Dictionary:
	return {
		"ok": true, "profile": p, "result": result, "tick": t,
		"snapshot": Rules.public_snapshot(p, account),
		"pending": Rules.pending(p, now),
		"closed_level": p["closed_level"], "hero_level": p["hero"]["level"],
	}
