class_name Net
extends Node
## Minimal JSON-over-HTTP client for the game server (works on desktop, mobile and web).
## Each call returns {"status": int, "data": Dictionary} (status 0 = no connection).

var base_url := ""
var token := ""
var timeout := 15.0

func request(method: int, path: String, body = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url.rstrip("/") + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"status": 0, "data": {"ok": false, "error": "request failed (%d)" % err}}
	var res: Array = await http.request_completed
	http.queue_free()
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else {}
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "data": {"ok": false, "error": "нет связи с сервером"}}
	if typeof(data) != TYPE_DICTIONARY:
		data = {"ok": false, "error": "bad response"}
	return {"status": code, "data": data}

func get_json(path: String) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, path)

func post_json(path: String, body: Dictionary) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, path, body)
