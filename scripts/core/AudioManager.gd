class_name AudioManager
extends Node

## Procedural 8-bit chiptune sound effect synthesizer for retro 4X strategy game.
## Generates classic square, triangle, and noise waveforms dynamically into AudioStreamWAV.

var players: Array[AudioStreamPlayer] = []
const POOL_SIZE = 8
var _pool_idx: int = 0
var bgm_player: AudioStreamPlayer
var bgm_stream: AudioStreamWAV

# Sound cache
var sfx_click: AudioStreamWAV
var sfx_move: AudioStreamWAV
var sfx_melee: AudioStreamWAV
var sfx_ranged: AudioStreamWAV
var sfx_impact: AudioStreamWAV
var sfx_death: AudioStreamWAV
var sfx_upgrade: AudioStreamWAV
var sfx_camp_cleared: AudioStreamWAV
var sfx_turn: AudioStreamWAV
var sfx_tech: AudioStreamWAV
var sfx_found: AudioStreamWAV

var _cfg: Node = null

func _get_cfg() -> Node:
	if not _cfg and is_inside_tree():
		_cfg = get_node_or_null("/root/GameConfig")
	return _cfg

func _ready() -> void:
	# Create pool of players
	for i in range(POOL_SIZE):
		var p = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)
	
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "Master"
	add_child(bgm_player)

	_generate_all_sfx()
	_generate_bgm()

	var cfg = _get_cfg()
	if cfg and cfg.music_enabled:
		start_bgm()

func _play_stream(stream: AudioStreamWAV, volume_db: float = 0.0) -> void:
	var cfg = _get_cfg()
	if cfg and not cfg.sfx_enabled:
		return
	if not stream or players.is_empty():
		return
	var player = players[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	player.stream = stream
	player.volume_db = volume_db
	player.play()

func start_bgm() -> void:
	if not bgm_player or not bgm_stream:
		return
	var cfg = _get_cfg()
	if cfg and not cfg.music_enabled:
		return
	bgm_player.stream = bgm_stream
	bgm_player.volume_db = -18.0
	bgm_player.play()

func stop_bgm() -> void:
	if bgm_player:
		bgm_player.stop()

func set_music_enabled(enabled: bool) -> void:
	var cfg = Engine.get_main_loop().root.get_node_or_null("/root/GameConfig")
	if cfg:
		cfg.music_enabled = enabled
		cfg.save_settings()
	if enabled:
		start_bgm()
	else:
		stop_bgm()

func set_sfx_enabled(enabled: bool) -> void:
	var cfg = Engine.get_main_loop().root.get_node_or_null("/root/GameConfig")
	if cfg:
		cfg.sfx_enabled = enabled
		cfg.save_settings()

# -------------------------------------------------------------
# PUBLIC API
# -------------------------------------------------------------
func play_ui_click() -> void:
	_play_stream(sfx_click, -16.0)

func play_unit_move() -> void:
	_play_stream(sfx_move, -18.0)

func play_attack_melee() -> void:
	_play_stream(sfx_melee, -10.0)

func play_ranged_fire() -> void:
	_play_stream(sfx_ranged, -12.0)

func play_projectile_hit() -> void:
	_play_stream(sfx_impact, -12.0)

func play_unit_death() -> void:
	_play_stream(sfx_death, -10.0)

func play_upgrade() -> void:
	_play_stream(sfx_upgrade, -12.0)

func play_camp_cleared() -> void:
	_play_stream(sfx_camp_cleared, -12.0)

func play_turn_start() -> void:
	_play_stream(sfx_turn, -16.0)

func play_tech_researched() -> void:
	_play_stream(sfx_tech, -12.0)

func play_city_founded() -> void:
	_play_stream(sfx_found, -12.0)

# -------------------------------------------------------------
# SYNTHESIZER GENERATION ROUTINES
# -------------------------------------------------------------
func _generate_all_sfx() -> void:
	sfx_click = _synth_soft_click(680.0, 440.0, 0.035)
	sfx_move = _synth_step(180.0, 0.055)
	sfx_melee = _synth_crunch(130.0, 0.13)
	sfx_ranged = _synth_chirp(380.0, 720.0, 0.11)
	sfx_impact = _synth_hit(0.09)
	sfx_death = _synth_descending([300.0, 240.0, 180.0, 130.0], 0.22)
	sfx_upgrade = _synth_arpeggio([261.6, 329.6, 392.0, 523.3, 659.3], 0.06, "triangle")
	sfx_camp_cleared = _synth_arpeggio([392.0, 523.3, 659.3, 784.0], 0.07, "triangle")
	sfx_turn = _synth_chime([523.3, 659.3], 0.09)
	sfx_tech = _synth_arpeggio([330.0, 415.3, 493.9, 659.3], 0.07, "triangle")
	sfx_found = _synth_arpeggio([261.6, 329.6, 392.0, 523.3], 0.07, "triangle")

func _synth_soft_click(f_start: float, f_end: float, duration: float) -> AudioStreamWAV:
	var rate = 22050
	var samples = int(rate * duration)
	var bytes = PackedByteArray()
	bytes.resize(samples)
	for i in range(samples):
		var prog = float(i) / float(samples)
		var freq = lerpf(f_start, f_end, prog)
		var t = float(i) / float(rate)
		var env = sin(prog * PI) * exp(-prog * 10.0)
		var val = sin(2.0 * PI * freq * t)
		bytes[i] = clampi(int(128 + val * env * 24.0), 0, 255)
	return _make_wav(bytes, rate)

func _synth_step(freq: float, duration: float) -> AudioStreamWAV:
	var rate = 22050
	var samples = int(rate * duration)
	var bytes = PackedByteArray()
	bytes.resize(samples)
	for i in range(samples):
		var prog = float(i) / float(samples)
		var t = float(i) / float(rate)
		var cur_freq = lerpf(freq, freq * 0.65, prog)
		var env = sin(prog * PI) * exp(-prog * 14.0)
		var val = sin(2.0 * PI * cur_freq * t)
		bytes[i] = clampi(int(128 + val * env * 26.0), 0, 255)
	return _make_wav(bytes, rate)

func _synth_chime(notes: Array, note_dur: float) -> AudioStreamWAV:
	var rate = 22050
	var note_samples = int(rate * note_dur)
	var total_samples = note_samples * notes.size()
	var bytes = PackedByteArray()
	bytes.resize(total_samples)
	for n in range(notes.size()):
		var freq: float = notes[n]
		for i in range(note_samples):
			var idx = n * note_samples + i
			var prog = float(i) / float(note_samples)
			var t = float(idx) / float(rate)
			var env = sin(prog * PI) * exp(-prog * 4.0)
			var val = sin(2.0 * PI * freq * t) + 0.2 * sin(4.0 * PI * freq * t)
			bytes[idx] = clampi(int(128 + val * env * 28.0), 0, 255)
	return _make_wav(bytes, rate)

func _synth_crunch(base_freq: float, duration: float) -> AudioStreamWAV:
	var rate = 22050
	var samples = int(rate * duration)
	var bytes = PackedByteArray()
	bytes.resize(samples)
	for i in range(samples):
		var prog = float(i) / float(samples)
		var env = (1.0 - prog) * (1.0 - prog)
		var t = float(i) / float(rate)
		var square = 1.0 if fmod(t * base_freq * (1.0 - prog * 0.5), 1.0) < 0.5 else -1.0
		var noise = (randf() * 2.0 - 1.0)
		var val = square * 0.4 + noise * 0.4
		bytes[i] = clampi(int(128 + val * env * 36.0), 0, 255)
	return _make_wav(bytes, rate)

func _synth_chirp(f_start: float, f_end: float, duration: float) -> AudioStreamWAV:
	var rate = 22050
	var samples = int(rate * duration)
	var bytes = PackedByteArray()
	bytes.resize(samples)
	for i in range(samples):
		var prog = float(i) / float(samples)
		var freq = lerpf(f_start, f_end, prog * prog)
		var t = float(i) / float(rate)
		var env = sin(prog * PI) * exp(-prog * 3.0)
		var val = sin(2.0 * PI * freq * t)
		bytes[i] = clampi(int(128 + val * env * 30.0), 0, 255)
	return _make_wav(bytes, rate)

func _synth_hit(duration: float) -> AudioStreamWAV:
	var rate = 22050
	var samples = int(rate * duration)
	var bytes = PackedByteArray()
	bytes.resize(samples)
	for i in range(samples):
		var prog = float(i) / float(samples)
		var env = exp(-prog * 10.0)
		var noise = (randf() * 2.0 - 1.0)
		var punch = sin(float(i) * 0.04)
		var val = noise * 0.6 + punch * 0.4
		bytes[i] = clampi(int(128 + val * env * 36.0), 0, 255)
	return _make_wav(bytes, rate)

func _synth_descending(freqs: Array, total_dur: float) -> AudioStreamWAV:
	var rate = 22050
	var samples = int(rate * total_dur)
	var bytes = PackedByteArray()
	bytes.resize(samples)
	var step_samples = samples / freqs.size()
	for i in range(samples):
		var note_idx = mini(i / step_samples, freqs.size() - 1)
		var freq = freqs[note_idx]
		var prog = float(i) / float(samples)
		var t = float(i) / float(rate)
		var env = 1.0 - prog
		var phase = fmod(t * freq, 1.0)
		var val = 4.0 * absf(phase - 0.5) - 1.0
		bytes[i] = clampi(int(128 + val * env * 32.0), 0, 255)
	return _make_wav(bytes, rate)

func _synth_arpeggio(notes: Array, note_dur: float, wave_type: String) -> AudioStreamWAV:
	var rate = 22050
	var note_samples = int(rate * note_dur)
	var total_samples = note_samples * notes.size()
	var bytes = PackedByteArray()
	bytes.resize(total_samples)
	for n in range(notes.size()):
		var freq: float = notes[n]
		for i in range(note_samples):
			var idx = n * note_samples + i
			var prog = float(i) / float(note_samples)
			var t = float(idx) / float(rate)
			var env = sin(prog * PI) * exp(-prog * 2.0)
			var val = 0.0
			if wave_type == "sine":
				val = sin(2.0 * PI * freq * t)
			else:
				var phase = fmod(t * freq, 1.0)
				val = 4.0 * absf(phase - 0.5) - 1.0
			bytes[idx] = clampi(int(128 + val * env * 32.0), 0, 255)
	return _make_wav(bytes, rate)

func _generate_bgm() -> void:
	# 4-measure calm retro ambient arpeggiated loop
	var chord_notes = [
		[261.63, 329.63, 392.0, 523.25], # C maj
		[220.00, 261.63, 329.63, 440.0], # A min
		[174.61, 220.00, 261.63, 349.23],# F maj
		[196.00, 246.94, 293.66, 392.0]  # G maj
	]
	var rate = 11025
	var note_dur = 0.25 # seconds per note
	var total_notes = chord_notes.size() * 8 # 32 notes = 8 seconds loop
	var total_samples = int(rate * total_notes * note_dur)
	var bytes = PackedByteArray()
	bytes.resize(total_samples)

	var note_samples = int(rate * note_dur)
	for n in range(total_notes):
		var chord_idx = (n / 8) % chord_notes.size()
		var chord = chord_notes[chord_idx]
		var note_in_chord = n % 4
		var freq: float = chord[note_in_chord]
		for i in range(note_samples):
			var idx = n * note_samples + i
			if idx >= total_samples:
				break
			var prog = float(i) / float(note_samples)
			var t = float(idx) / float(rate)
			var env = sin(prog * PI) * exp(-prog * 1.5)
			var phase = fmod(t * freq, 1.0)
			var val = 4.0 * absf(phase - 0.5) - 1.0
			bytes[idx] = clampi(int(128 + val * env * 18.0), 0, 255)

	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total_samples
	bgm_stream = wav

func _make_wav(data: PackedByteArray, sample_rate: int) -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data
	return wav
