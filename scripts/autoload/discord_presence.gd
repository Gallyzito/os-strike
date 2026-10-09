extends Node
## Discord Rich Presence (o que aparece no perfil do Discord: "A jogar os!strike").
##
## O Godot não consegue abrir o pipe do Discord (\\.\pipe\discord-ipc-N), por
## isso arranca-se um pequeno ajudante em PowerShell (vem com o Windows) que
## recebe os comandos por stdin, uma linha JSON cada, e passa-os ao Discord.
## Se o Discord não estiver aberto, o ajudante volta a tentar a cada atualização.
##
## Para funcionar é preciso o "Application ID" de uma aplicação criada em
## https://discord.com/developers/applications (o nome da aplicação é o que
## aparece como "A jogar ...") com uma imagem "logo" em Rich Presence → Art Assets.

## ID da aplicação do Discord (Settings "discord/client_id" sobrepõe-se a este).
const CLIENT_ID := "1558089412124876891"
## O Discord só aceita 5 atualizações a cada 20 s.
const MIN_INTERVAL := 4.0

const HELPER := r'''
param([string]$ClientId)
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
function Send($p, $op, $json) {
	$b = [Text.Encoding]::UTF8.GetBytes($json)
	$h = [BitConverter]::GetBytes([int]$op) + [BitConverter]::GetBytes([int]$b.Length)
	$p.Write($h, 0, 8); $p.Write($b, 0, $b.Length); $p.Flush()
}
function Recv($p) {
	$h = New-Object byte[] 8; $r = 0
	while ($r -lt 8) { $n = $p.Read($h, $r, 8 - $r); if ($n -le 0) { throw 'closed' }; $r += $n }
	$len = [BitConverter]::ToInt32($h, 4); $b = New-Object byte[] $len; $r = 0
	while ($r -lt $len) { $n = $p.Read($b, $r, $len - $r); if ($n -le 0) { throw 'closed' }; $r += $n }
	return [Text.Encoding]::UTF8.GetString($b)
}
function Open-Discord {
	for ($i = 0; $i -lt 10; $i++) {
		try {
			$p = New-Object IO.Pipes.NamedPipeClientStream('.', "discord-ipc-$i", [IO.Pipes.PipeDirection]::InOut)
			$p.Connect(300)
			Send $p 0 ('{"v":1,"client_id":"' + $ClientId + '"}')
			$reply = Recv $p
			[Console]::Out.WriteLine('READY ' + $reply); [Console]::Out.Flush()
			return $p
		} catch { }
	}
	return $null
}
$pipe = $null
while ($true) {
	$line = [Console]::In.ReadLine()
	if ($line -eq $null) { break }
	if ($pipe -eq $null) { $pipe = Open-Discord }
	if ($pipe -eq $null) { [Console]::Out.WriteLine('NODISCORD'); [Console]::Out.Flush(); continue }
	try { Send $pipe 1 $line; $r = Recv $pipe; [Console]::Out.WriteLine('OK ' + $r) }
	catch { [Console]::Out.WriteLine('LOST'); try { $pipe.Dispose() } catch { }; $pipe = $null }
	[Console]::Out.Flush()
}
'''

## Últimas respostas do ajudante (para depurar).
var last_reply := ""

var _pid := -1
var _stdio: FileAccess
var _pending := {}
var _has_pending := false
var _last_send := -100.0
var _start := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start = int(Time.get_unix_time_from_system())


func client_id() -> String:
	var id := String(Settings.get_value("discord/client_id")).strip_edges()
	return id if not id.is_empty() else CLIENT_ID


func enabled() -> bool:
	return OS.get_name() == "Windows" and bool(Settings.get_value("discord/enabled")) and not client_id().is_empty()


## Muda o que aparece no Discord. `details` = 1.ª linha, `state` = 2.ª linha.
## `end_in`: segundos até acabar (mostra "faltam m:ss"); `small`: texto do ícone pequeno.
func set_status(details: String, state := "", end_in := -1.0, small := "") -> void:
	var activity := {
		"details": details.left(127),
		"assets": {"large_image": "logo", "large_text": "os!strike"},
		"timestamps": {"start": _start},
	}
	if not state.is_empty():
		activity["state"] = state.left(127)
	if end_in > 0.0:
		activity["timestamps"] = {"end": int(Time.get_unix_time_from_system() + end_in)}
	if not small.is_empty():
		activity.assets["small_image"] = "logo"
		activity.assets["small_text"] = small.left(127)
	_pending = activity
	_has_pending = true


func clear() -> void:
	_pending = {}
	_has_pending = true


func _process(_delta: float) -> void:
	_drain()
	var now := Time.get_ticks_msec() / 1000.0
	if not _has_pending or now - _last_send < MIN_INTERVAL or not enabled():
		return
	if _pid < 0 and not _start_helper():
		return
	var cmd := {"cmd": "SET_ACTIVITY", "nonce": str(Time.get_ticks_usec()),
		"args": {"pid": OS.get_process_id(), "activity": _pending if not _pending.is_empty() else null}}
	_stdio.store_line(_ascii_json(cmd))
	_stdio.flush()
	_has_pending = false
	_last_send = now


## JSON só com ASCII (os outros caracteres como \uXXXX): assim "·" e "★" chegam
## bem ao Discord seja qual for a codificação da consola.
static func _ascii_json(data: Variant) -> String:
	var text := JSON.stringify(data)
	var out := ""
	for ch in text:
		var code := ch.unicode_at(0)
		if code < 128:
			out += ch
		elif code <= 0xFFFF:
			out += "\\u%04x" % code
		else:
			code -= 0x10000
			out += "\\u%04x\\u%04x" % [0xD800 + (code >> 10), 0xDC00 + (code & 0x3FF)]
	return out


func _start_helper() -> bool:
	var path := OS.get_user_data_dir().path_join("discord_rpc.ps1")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(HELPER)
	f.close()
	var info := OS.execute_with_pipe("powershell.exe",
		["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", path, client_id()], false)
	if info.is_empty():
		return false
	_pid = int(info.pid)
	_stdio = info.stdio
	return true


## Lê o que o ajudante respondeu (para o pipe dele não encher).
func _drain() -> void:
	if _stdio == null:
		return
	if not OS.is_process_running(_pid):
		_pid = -1
		_stdio = null
		return
	var data := _stdio.get_buffer(4096)
	if not data.is_empty():
		last_reply = (last_reply + "\n" + data.get_string_from_utf8().strip_edges()).right(600)


func _exit_tree() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
