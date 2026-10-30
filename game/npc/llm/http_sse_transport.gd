class_name HTTPSSETransport
extends LLMTransport
## Real transport: Godot HTTPClient (HTTPRequest cannot stream). Poll-driven.

var _client: HTTPClient = HTTPClient.new()
var _parser: SSEParser = SSEParser.new()
var _url: String = ""
var _headers: PackedStringArray
var _body: String = ""
var _path: String = "/"
var _sent: bool = false
var _done: bool = false
var _status: int = 0
var _err_body: String = ""


func start(url: String, headers: PackedStringArray, body: String) -> void:
	_url = url
	_headers = headers
	_body = body
	var use_tls: bool = url.begins_with("https://")
	var rest: String = url.substr(url.find("://") + 3)
	var slash: int = rest.find("/")
	var host_port: String = rest if slash < 0 else rest.substr(0, slash)
	_path = "/" if slash < 0 else rest.substr(slash)
	var host: String = host_port
	var port: int = 443 if use_tls else 80
	if ":" in host_port:
		host = host_port.get_slice(":", 0)
		port = int(host_port.get_slice(":", 1))
	var tls: TLSOptions = TLSOptions.client() if use_tls else null
	var err: int = _client.connect_to_host(("https://" if use_tls else "http://") + host, port, tls)
	if err != OK:
		_finish(false, "connect_failed:%d" % err)


func poll() -> void:
	if _done:
		return
	var err: int = _client.poll()
	if err != OK:
		_finish(false, "poll_failed:%d" % err)
		return
	match _client.get_status():
		HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, \
		HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_finish(false, "network_error:%d" % _client.get_status())
		HTTPClient.STATUS_CONNECTED:
			if not _sent:
				_sent = true
				var rerr: int = _client.request(HTTPClient.METHOD_POST, _path, _headers, _body)
				if rerr != OK:
					_finish(false, "request_failed:%d" % rerr)
		HTTPClient.STATUS_BODY:
			_status = _client.get_response_code()
			var chunk: PackedByteArray = _client.read_response_body_chunk()
			if chunk.size() > 0:
				var text: String = chunk.get_string_from_utf8()
				if _status >= 400:
					_err_body += text
				else:
					for payload in _parser.feed(text):
						data_received.emit(payload)
		HTTPClient.STATUS_DISCONNECTED:
			if _sent:
				_finish_response()
	if not _done and _sent and _client.get_status() == HTTPClient.STATUS_CONNECTED:
		_finish_response()


func cancel() -> void:
	_client.close()
	_done = true


func _finish_response() -> void:
	if _status == 0:
		_status = _client.get_response_code()
	if _status >= 400 or _status == 0:
		_finish(false, "http_%d:%s" % [_status, _err_body.left(300)])
	else:
		_finish(true, "")


func _finish(ok: bool, error: String) -> void:
	if _done:
		return
	_done = true
	_client.close()
	finished.emit(ok, error)
