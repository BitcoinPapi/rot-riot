extends Node
## ============================================================================
##  SOUND EFFECTS
##
##  All sounds are synthesised here from noise bursts and simple tones when
##  the game starts (on a background thread, so there is no loading pause).
##  Nothing is sampled or copied from anywhere.
##
##  Play one with:   Sfx.play("pistol")
##
##  REPLACING A SOUND WITH A REAL RECORDING:
##  Put a file with the same name in  res://assets/sfx/  - for example
##  assets/sfx/shotgun.wav (or .ogg) - and it is used instead.
##  The names are the keys of RECIPES below.
##  SEVERAL RECORDINGS OF ONE SOUND: name them shotgun_1.ogg, shotgun_2.ogg,
##  shotgun_3.ogg ... and a different one is picked each time, so a sound
##  heard many times a second does not repeat itself. The generated sounds
##  are as loud as they can be without distorting (peak -1 dB); a recording
##  should be too, then the volumes below still fit.
##  Which recordings are in use and where they come from: assets/CREDITS.txt
##  RECORDINGS THAT MAY NOT BE SHARED (bought sound packs, or free ones whose
##  licence forbids passing the files on): they must not go into the game's
##  public project. Put them in the game's own save folder instead, in a
##  folder called "sfx" (user://sfx/, PRIVATE_FOLDER below) - same names, same
##  rules. Files there win over everything else and survive every update.
## ============================================================================

const SAMPLE_RATE := 32000
const VOICES := 20                    # how many sounds can overlap

## name -> [function that builds it, volume in dB, minimum seconds between plays]
## The gap stops 30 zombies hit in one frame from playing 30 sounds at once.
var RECIPES := {
	"pistol": [_make_pistol, -3.5, 0.03],
	"shotgun": [_make_shotgun, 0.0, 0.05],
	"machinegun": [_make_machinegun, -6.5, 0.03],
	"launcher": [_make_launcher, -2.0, 0.05],
	"smg": [_make_smg, -7.0, 0.03],
	"rifle": [_make_rifle, 0.0, 0.05],
	"flame": [_make_flame, -7.0, 0.1],
	"chainsaw": [_make_chainsaw, -10.0, 0.12],
	"chainsaw_hit": [_make_chainsaw_hit, -5.0, 0.09],
	"explosion": [_make_explosion, 1.0, 0.07],
	"sledge_swing": [_make_sledge_swing, -5.0, 0.05],
	"sledge_hit": [_make_sledge_hit, 0.0, 0.05],
	"ricochet": [_make_ricochet, -8.0, 0.08],
	"zombie_hit": [_make_zombie_hit, -6.0, 0.045],
	"zombie_die": [_make_zombie_die, -4.0, 0.05],
	"boss_roar": [_make_boss_roar, 0.0, 0.3],
	"boss_charge": [_make_boss_charge, -1.0, 0.3],
	"gobber_windup": [_make_gobber_windup, -5.0, 0.12],
	"spit": [_make_spit, -4.0, 0.1],
	"spit_hit": [_make_spit_hit, -6.0, 0.1],
	"chucker_windup": [_make_chucker_windup, -3.0, 0.2],
	"lob_throw": [_make_lob_throw, -4.0, 0.12],
	"lob_land": [_make_lob_land, -1.0, 0.15],
	"gasbag_fuse": [_make_gasbag_fuse, -4.0, 0.2],
	"gas_burst": [_make_gas_burst, 0.0, 0.15],
	"lunger_shriek": [_make_lunger_shriek, -4.0, 0.12],
	"player_hurt": [_make_player_hurt, -1.0, 0.1],
	"player_die": [_make_player_die, 0.0, 0.5],
	"coin": [_make_coin, -6.0, 0.03],
	"pickup_weapon": [_make_pickup_weapon, -3.0, 0.1],
	"weapon_expire": [_make_weapon_expire, -6.0, 0.1],
	"medkit": [_make_medkit, -4.0, 0.1],
	"crate_spawn": [_make_crate_spawn, -6.0, 0.1],
	"crate_hit": [_make_crate_hit, -6.0, 0.05],
	"crate_break": [_make_crate_break, -2.0, 0.2],
	"second_wind": [_make_second_wind, 1.0, 0.3],
	"wave_start": [_make_wave_start, -4.0, 0.3],
	"wave_clear": [_make_wave_clear, -4.0, 0.3],
	"game_over": [_make_game_over, -2.0, 0.5],
	"mag_out": [_make_mag_out, -7.0, 0.04],
	"mag_in": [_make_mag_in, -5.0, 0.04],
	"rack": [_make_rack, -4.0, 0.04],
	"shell_in": [_make_shell_in, -5.0, 0.04],
	"hiss": [_make_hiss, -8.0, 0.1],
	"level_up": [_make_level_up, -2.0, 0.3],
	"weapon_level": [_make_weapon_level, -4.0, 0.2],
	"dodge": [_make_dodge, -5.0, 0.1],
	"pet_bite": [_make_pet_bite, -7.0, 0.08],
	"pet_call": [_make_pet_call, -3.0, 0.3],
	"gear_drop": [_make_gear_drop, -3.0, 0.2],
	"gear_pickup": [_make_gear_pickup, -3.0, 0.2],
	"chest_open": [_make_chest_open, -2.0, 0.04],
	"forge_ok": [_make_forge_ok, -2.0, 0.2],
	"forge_fail": [_make_forge_fail, -2.0, 0.2],
	"forge_break": [_make_forge_break, -1.0, 0.2],
	"crit": [_make_crit, -7.0, 0.07],
	"ui_move": [_make_ui_move, -10.0, 0.03],
	"ui_click": [_make_ui_click, -6.0, 0.03],
	"ui_buy": [_make_ui_buy, -4.0, 0.05],
	"ui_deny": [_make_ui_deny, -6.0, 0.05],
}

## Recordings in assets/sfx (see the top of this file) that are quieter or
## louder to the ear than the generated sound they replace: dB added on top of
## the volume in RECIPES. (Measured, not heard: average loudness against the
## generated sound's.)
const RECORDING_GAIN := {
	"shotgun": 3.0,          # a real shot is one sharp crack and a tail; the generated one was a full second of roar
	"sledge_hit": 5.0,       # the big hit must stay the big hit
	"crate_break": 2.0,
	"ricochet": -5.0,
	"ui_click": 4.0,
	"ui_move": 3.0,
	"ui_deny": 3.0,
}

const PRIVATE_FOLDER := "user://sfx/"    # recordings only this player has (see the top of this file)
const SHARED_FOLDER := "res://assets/sfx/"

var ready_to_play := false

var _streams := {}        # name -> AudioStream
var _variants := {}       # name -> Array of AudioStream: several recordings of one sound (one is picked each time)
var _recorded := {}       # name -> true for every sound that is played from a recording
var _last_played := {}    # name -> time in ms
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _task_id := -1
var _shut_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	# Real recordings in assets/sfx override the synth.
	for sound: String in RECIPES.keys():
		var found: Array[AudioStream] = []
		for folder: String in [PRIVATE_FOLDER, SHARED_FOLDER]:
			var single := _recording(folder + sound)
			if single != null:
				found.append(single)
			var number := 1
			while true:
				var next := _recording("%s%s_%d" % [folder, sound, number])
				if next == null:
					break
				found.append(next)
				number += 1
			if not found.is_empty():
				break                     # (the private folder wins)
		if not found.is_empty():
			_streams[sound] = found[0]
			_recorded[sound] = true
			if found.size() > 1:
				_variants[sound] = found
	_task_id = WorkerThreadPool.add_task(_generate_all, false, "Synthesising sound effects")


## The recording at `path` (without its ending), or null if there is none.
func _recording(path: String) -> AudioStream:
	for ext: String in ["wav", "ogg", "mp3"]:
		var file := "%s.%s" % [path, ext]
		if path.begins_with("user://"):
			# (A plain file on the player's disk, read as it is.)
			if not FileAccess.file_exists(file):
				continue
			match ext:
				"ogg":
					return AudioStreamOggVorbis.load_from_file(file)
				"wav":
					return AudioStreamWAV.load_from_file(file)
				_:
					var mp3 := AudioStreamMP3.new()
					mp3.data = FileAccess.get_file_as_bytes(file)
					return mp3
		elif ResourceLoader.exists(file):
			return load(file)
	return null


## True if `sound` is played from a recording (not generated).
func is_recording(sound: String) -> bool:
	return _recorded.has(sound)


## How many recordings `sound` has to pick from (0 = it is generated).
func recording_count(sound: String) -> int:
	if _variants.has(sound):
		return (_variants[sound] as Array).size()
	return 1 if is_recording(sound) else 0


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	stop_all()


func _setup_buses() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")
	# A limiter on the master bus keeps big moments from distorting.
	if AudioServer.get_bus_effect_count(0) == 0:
		AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	SaveData.apply_settings()


# ----------------------------------------------------------------------------
#  Playing
# ----------------------------------------------------------------------------
## Play a sound. `pitch_variation` randomises the pitch a little so repeated
## sounds (gunshots, hits) don't sound robotic.
func play(sound: String, volume_db: float = 0.0, pitch_variation: float = 0.08) -> void:
	play_pitched(sound, 1.0 + randf_range(-pitch_variation, pitch_variation), volume_db)


func play_pitched(sound: String, pitch: float, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null or _shut_down:
		return   # not generated yet, unknown name, or the game is closing
	var recipe: Array = RECIPES.get(sound, [null, 0.0, 0.03])
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -100000)) < int(float(recipe[2]) * 1000.0):
		return
	_last_played[sound] = now

	# Take the next free voice; if all are busy, the oldest one is reused.
	var player := _players[_next_player]
	for i in VOICES:
		var candidate := _players[(_next_player + i) % VOICES]
		if not candidate.playing:
			player = candidate
			break
	_next_player = (_next_player + 1) % VOICES
	if _variants.has(sound):
		stream = (_variants[sound] as Array).pick_random()
	player.stream = stream
	player.volume_db = volume_db + float(recipe[1])
	if _recorded.has(sound):
		player.volume_db += float(RECORDING_GAIN.get(sound, 0.0))
	player.pitch_scale = clampf(pitch, 0.3, 3.0)
	player.play()


## Silence everything for good (called just before the game closes).
func stop_all() -> void:
	_shut_down = true
	for p: AudioStreamPlayer in _players:
		p.stop()
		p.stream = null


## Used by developer tools: every generated sound as name -> AudioStreamWAV.
func get_streams() -> Dictionary:
	return _streams


# ----------------------------------------------------------------------------
#  Synthesis (runs on a worker thread)
# ----------------------------------------------------------------------------
func _generate_all() -> void:
	var built := {}
	var index := 0
	for sound: String in RECIPES.keys():
		index += 1
		if _streams.has(sound):
			continue   # replaced by a real file
		var recipe: Array = RECIPES[sound]
		var maker: Callable = recipe[0]
		var synth := Synth.new(index * 7919)
		maker.call(synth)
		built[sound] = synth.to_bytes()
	_install.call_deferred(built)


func _install(built: Dictionary) -> void:
	for sound: String in built.keys():
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = SAMPLE_RATE
		wav.stereo = false
		wav.data = built[sound]
		_streams[sound] = wav
	ready_to_play = true


## A tiny synthesiser: layers of filtered noise and gliding tones in one buffer.
class Synth:
	const SR := 32000.0
	const SINE := 0
	const TRIANGLE := 1
	const SAW := 2
	const SQUARE := 3

	var buf := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	var drive := 0.0       # > 0 adds grit and punch (soft clipping)

	func _init(seed_value: int) -> void:
		rng.seed = seed_value

	func length(seconds: float) -> void:
		buf.resize(int(seconds * SR))
		buf.fill(0.0)

	## A burst of noise. Its brightness glides from `lp_from` to `lp_to` (Hz);
	## `tau` is how quickly it dies away; `hp` removes rumble below that pitch.
	func noise(start: float, dur: float, amp: float, tau: float, lp_from: float, lp_to: float,
			attack: float = 0.002, hp: float = 0.0) -> void:
		var i0 := int(start * SR)
		var n := mini(int(dur * SR), buf.size() - i0)
		if n <= 0:
			return
		var y := 0.0
		var y2 := 0.0
		var hp_y := 0.0
		var hp_a := 1.0 - exp(-TAU * hp / SR) if hp > 0.0 else 0.0
		var ratio := lp_to / lp_from
		var a := 1.0 - exp(-TAU * lp_from / SR)
		var attack_n := maxf(attack * SR, 1.0)
		var decay := exp(-1.0 / maxf(tau * SR, 1.0))
		var env := 1.0
		var release_n := minf(0.005 * SR, float(n) * 0.25)
		for k in n:
			if (k & 31) == 0:
				var fc := lp_from * pow(ratio, float(k) / float(n))
				a = 1.0 - exp(-TAU * fc / SR)
			# Two gentle filters in a row give a rounder, less hissy tone.
			y += a * (rng.randf() * 2.0 - 1.0 - y)
			y2 += a * (y - y2)
			var s := y2
			if hp > 0.0:
				hp_y += hp_a * (s - hp_y)
				s -= hp_y
			var gain: float
			if k < attack_n:
				gain = float(k) / attack_n
			else:
				env *= decay
				gain = env
			if k > n - release_n:
				gain *= float(n - k) / release_n
			buf[i0 + k] += s * gain * amp

	## A burst of noise squeezed around one pitch (`centre` Hz) - like air
	## ringing in a barrel or a tube. It gives a sound a "voice" of its own
	## without any gliding tone. `q` is how narrow the ring is (1 = wide and
	## breathy, 10 = almost a note); `tau` is how quickly it dies away.
	func band(start: float, dur: float, amp: float, tau: float, centre: float, q: float, attack: float = 0.001) -> void:
		var i0 := int(start * SR)
		var n := mini(int(dur * SR), buf.size() - i0)
		if n <= 0:
			return
		var w0 := TAU * centre / SR
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		var b0 := alpha / a0
		var a1 := -2.0 * cos(w0) / a0
		var a2 := (1.0 - alpha) / a0
		var x1 := 0.0
		var x2 := 0.0
		var y1 := 0.0
		var y2 := 0.0
		var attack_n := maxf(attack * SR, 1.0)
		var decay := exp(-1.0 / maxf(tau * SR, 1.0))
		var env := 1.0
		var release_n := minf(0.005 * SR, float(n) * 0.25)
		# A narrow filter lets little through, so make up for it.
		var makeup := amp * sqrt(q) * 2.0
		for k in n:
			var x := rng.randf() * 2.0 - 1.0
			var y := b0 * (x - x2) - a1 * y1 - a2 * y2
			x2 = x1
			x1 = x
			y2 = y1
			y1 = y
			var gain: float
			if k < attack_n:
				gain = float(k) / attack_n
			else:
				env *= decay
				gain = env
			if k > n - release_n:
				gain *= float(n - k) / release_n
			buf[i0 + k] += y * gain * makeup

	## A tone whose pitch glides from `f_from` to `f_to` (Hz).
	func tone(start: float, dur: float, amp: float, f_from: float, f_to: float, tau: float,
			wave: int = SINE, attack: float = 0.003, vib_rate: float = 0.0, vib_depth: float = 0.0) -> void:
		var i0 := int(start * SR)
		var n := mini(int(dur * SR), buf.size() - i0)
		if n <= 0:
			return
		var phase := 0.0
		var freq := f_from
		var freq_step := pow(f_to / f_from, 1.0 / float(n))
		var attack_n := maxf(attack * SR, 1.0)
		var decay := exp(-1.0 / maxf(tau * SR, 1.0))
		var env := 1.0
		var release_n := minf(0.006 * SR, float(n) * 0.25)
		var vib_step := TAU * vib_rate / SR
		for k in n:
			var f := freq
			if vib_rate > 0.0:
				f *= 1.0 + vib_depth * sin(vib_step * float(k))
			phase += f / SR
			if phase >= 1.0:
				phase -= 1.0
			var s: float
			if wave == SINE:
				s = sin(phase * TAU)
			elif wave == TRIANGLE:
				s = 4.0 * absf(phase - 0.5) - 1.0
			elif wave == SAW:
				s = 2.0 * phase - 1.0
			else:
				s = 1.0 if phase < 0.5 else -1.0
			var gain: float
			if k < attack_n:
				gain = float(k) / attack_n
			else:
				env *= decay
				gain = env
			if k > n - release_n:
				gain *= float(n - k) / release_n
			buf[i0 + k] += s * gain * amp
			freq *= freq_step

	## Muffle the whole sound above `hz`.
	func lowpass(hz: float) -> void:
		var a := 1.0 - exp(-TAU * hz / SR)
		var y := 0.0
		var y2 := 0.0
		for k in buf.size():
			y += a * (buf[k] - y)
			y2 += a * (y - y2)
			buf[k] = y2

	## Add the echo of an open space: a handful of delayed, fading, slightly
	## muffled copies. `mix` is how loud the echo is, `decay` how many seconds
	## it takes to die away. This is most of what makes a dry burst of noise
	## sound like a real gunshot outdoors.
	func reverb(mix: float, decay: float, damp_hz: float = 2600.0) -> void:
		var n := buf.size()
		var wet := PackedFloat32Array()
		wet.resize(n)
		wet.fill(0.0)
		var a := 1.0 - exp(-TAU * damp_hz / SR)
		var line := PackedFloat32Array()
		line.resize(n)
		for d_sec: float in [0.0297, 0.0371, 0.0411, 0.0437, 0.0533, 0.0677]:
			var d := int(d_sec * SR)
			var g := pow(0.001, d_sec / decay)     # fades by 60 dB after `decay` seconds
			var lp := 0.0
			for k in n:
				var fb := line[k - d] if k >= d else 0.0
				lp += a * (fb - lp)
				var v := buf[k] + lp * g
				line[k] = v
				wet[k] += v - buf[k]
		# Two short "smearing" stages so the echoes blur together instead of ringing.
		for d_sec: float in [0.005, 0.0017]:
			var d := int(d_sec * SR)
			var g := 0.6
			line.fill(0.0)
			for k in n:
				var x_d := wet[k - d] if k >= d else 0.0
				var y_d := line[k - d] if k >= d else 0.0
				line[k] = -g * wet[k] + x_d + g * y_d
			for k in n:
				wet[k] = line[k]
		var gain := mix / 6.0
		for k in n:
			buf[k] += wet[k] * gain

	## Finish: optional soft clipping, normalise, convert to 16-bit samples.
	func to_bytes() -> PackedByteArray:
		var n := buf.size()
		var peak := 0.0001
		for k in n:
			var v := buf[k]
			if drive > 0.0:
				v = tanh(v * drive)
				buf[k] = v
			var av := absf(v)
			if av > peak:
				peak = av
		var scale := 0.89 / peak * 32767.0
		var bytes := PackedByteArray()
		bytes.resize(n * 2)
		for k in n:
			bytes.encode_s16(k * 2, int(buf[k] * scale))
		return bytes


# ----------------------------------------------------------------------------
#  The recipes. Each weapon is built to sound different - every gun has its
#  own pitch range (its "voice", made with Synth.band), its own length of
#  echo and its own mechanical click:
#    SMG         highest and shortest: a snappy "tack"
#    pistol      a dry mid bark, then the slide
#    rifle       a whip-crack with the longest, rolling echo, then the bolt
#    machine gun a low chugging thud with a clanking bolt
#    shotgun     the deepest boom with a long tail, then the pump
#    launcher    a hollow "thoomp" in a tube, then the explosion
#    sledgehammer = whoosh + heavy thud.
# ----------------------------------------------------------------------------
func _make_pistol(s: Synth) -> void:
	# A dry bark in the middle of the range with a short slap of echo, then
	# the slide snapping home. (crack + bark + thump + tail; no gliding high
	# tones - those are what make a gun sound like a laser.)
	s.length(0.5)
	s.drive = 2.0
	s.noise(0.0, 0.03, 1.8, 0.006, 9000.0, 5000.0, 0.0003, 1800.0)
	s.band(0.0, 0.16, 2.2, 0.03, 1500.0, 2.2)
	s.noise(0.0, 0.2, 1.2, 0.03, 4000.0, 900.0, 0.0005)
	s.tone(0.0, 0.12, 0.4, 150.0, 65.0, 0.035)
	s.noise(0.012, 0.45, 0.35, 0.15, 2000.0, 500.0, 0.01)
	s.reverb(0.32, 0.32)
	s.noise(0.058, 0.012, 0.42, 0.003, 9000.0, 6000.0, 0.0003, 3500.0)
	s.noise(0.074, 0.014, 0.34, 0.004, 7000.0, 4500.0, 0.0003, 2500.0)


func _make_shotgun(s: Synth) -> void:
	# The deepest and widest: a boom you feel, a long tail, then the pump
	# being racked back and forward.
	s.length(1.0)
	s.drive = 2.8
	s.noise(0.0, 0.03, 1.4, 0.007, 7000.0, 3500.0, 0.0003, 1500.0)
	s.band(0.0, 0.4, 2.6, 0.09, 330.0, 1.6)
	s.noise(0.0, 0.5, 1.8, 0.09, 2600.0, 380.0, 0.0005)
	s.tone(0.0, 0.42, 1.0, 92.0, 36.0, 0.13)
	s.noise(0.015, 0.65, 0.8, 0.26, 1100.0, 300.0, 0.01)
	s.reverb(0.42, 0.55, 2000.0)
	s.noise(0.37, 0.04, 0.8, 0.01, 4000.0, 2200.0, 0.001, 900.0)
	s.band(0.37, 0.05, 0.5, 0.012, 1250.0, 5.0)
	s.noise(0.48, 0.05, 1.0, 0.012, 3500.0, 1800.0, 0.001, 700.0)
	s.band(0.48, 0.06, 0.6, 0.014, 980.0, 5.0)


func _make_machinegun(s: Synth) -> void:
	# A heavy, chugging thud lower than the other automatics, with the bolt
	# clanking after every round. Dry, so rapid fire becomes a rattle.
	s.length(0.3)
	s.drive = 2.1
	s.noise(0.0, 0.018, 1.5, 0.004, 9000.0, 5000.0, 0.0003, 2500.0)
	s.band(0.0, 0.11, 2.6, 0.024, 720.0, 2.8)
	s.noise(0.0, 0.1, 1.2, 0.02, 3000.0, 900.0, 0.0005, 150.0)
	s.tone(0.0, 0.1, 0.6, 135.0, 60.0, 0.03)
	s.noise(0.01, 0.25, 0.25, 0.08, 1800.0, 600.0, 0.008)
	s.reverb(0.2, 0.2)
	s.band(0.036, 0.03, 0.55, 0.007, 3300.0, 9.0)
	s.noise(0.036, 0.02, 0.4, 0.005, 6000.0, 3500.0, 0.0005, 2000.0)


func _make_smg(s: Synth) -> void:
	# The lightest and highest: a quick, snappy "tack" with almost no body
	# and no tail, so a long burst purrs instead of roaring.
	s.length(0.2)
	s.drive = 1.6
	s.noise(0.0, 0.012, 1.8, 0.0025, 12000.0, 8000.0, 0.0003, 4000.0)
	s.band(0.0, 0.06, 2.4, 0.012, 3100.0, 2.6)
	s.noise(0.0, 0.05, 0.9, 0.01, 7000.0, 3000.0, 0.0005, 1200.0)
	s.tone(0.0, 0.035, 0.12, 190.0, 120.0, 0.012)
	s.noise(0.006, 0.14, 0.14, 0.045, 3500.0, 1400.0, 0.006, 500.0)
	s.reverb(0.12, 0.1)


func _make_rifle(s: Synth) -> void:
	# A whip-crack on top of a hard mid punch, a long echo that rolls away
	# and comes back off the tree line, then the bolt being worked.
	s.length(1.2)
	s.drive = 2.5
	s.noise(0.0, 0.035, 2.8, 0.008, 12000.0, 7000.0, 0.0002, 2500.0)
	s.band(0.0, 0.22, 2.0, 0.045, 1050.0, 1.4)
	s.noise(0.0, 0.35, 1.6, 0.05, 6500.0, 1200.0, 0.0005, 200.0)
	s.tone(0.0, 0.2, 0.5, 125.0, 50.0, 0.06)
	s.noise(0.015, 1.0, 0.8, 0.34, 3200.0, 700.0, 0.01, 250.0)
	s.noise(0.19, 0.5, 0.5, 0.14, 2400.0, 600.0, 0.02, 300.0)
	s.reverb(0.55, 1.0, 3200.0)
	s.noise(0.32, 0.04, 0.6, 0.01, 4500.0, 2500.0, 0.001, 1200.0)
	s.band(0.32, 0.05, 0.4, 0.012, 2100.0, 6.0)
	s.noise(0.42, 0.05, 0.75, 0.012, 4000.0, 2000.0, 0.001, 900.0)
	s.band(0.42, 0.06, 0.45, 0.014, 1700.0, 6.0)


func _make_flame(s: Synth) -> void:
	# A chunk of roaring gas. Chunks overlap while the trigger is held.
	s.length(0.42)
	s.noise(0.0, 0.4, 1.0, 0.25, 900.0, 1600.0, 0.08, 150.0)
	s.noise(0.0, 0.4, 0.5, 0.2, 3000.0, 5000.0, 0.1, 1500.0)


func _make_chainsaw(s: Synth) -> void:
	# A chunk of two-stroke engine buzz. Chunks overlap while it is running.
	s.length(0.3)
	s.drive = 2.2
	s.tone(0.0, 0.3, 0.7, 98.0, 104.0, 0.6, Synth.SAW, 0.02, 34.0, 0.06)
	s.tone(0.0, 0.3, 0.4, 196.0, 208.0, 0.6, Synth.SQUARE, 0.02, 34.0, 0.06)
	s.noise(0.0, 0.3, 0.6, 0.5, 2500.0, 3200.0, 0.02, 600.0)
	s.lowpass(3800.0)


func _make_chainsaw_hit(s: Synth) -> void:
	# The chain biting: a wet grind with three quick rips.
	s.length(0.2)
	s.drive = 1.6
	s.noise(0.0, 0.18, 1.6, 0.06, 2200.0, 600.0, 0.002)
	s.noise(0.0, 0.03, 0.8, 0.008, 8000.0, 4000.0, 0.0005, 2500.0)
	s.noise(0.05, 0.03, 0.7, 0.008, 8000.0, 4000.0, 0.0005, 2500.0)
	s.noise(0.1, 0.03, 0.6, 0.008, 8000.0, 4000.0, 0.0005, 2500.0)


func _make_launcher(s: Synth) -> void:
	# A grenade launcher really is a hollow, low "thoomp": air ringing in a
	# wide tube, a puff, and the clunk of the breech.
	s.length(0.5)
	s.drive = 1.5
	s.tone(0.0, 0.3, 0.7, 200.0, 88.0, 0.08)
	s.band(0.0, 0.3, 1.6, 0.07, 260.0, 4.5)
	s.noise(0.0, 0.2, 1.4, 0.04, 1600.0, 420.0, 0.001)
	s.noise(0.0, 0.08, 1.0, 0.02, 3200.0, 900.0, 0.0005, 300.0)
	s.noise(0.01, 0.3, 0.4, 0.1, 2400.0, 800.0, 0.01, 500.0)
	s.reverb(0.25, 0.3)
	s.band(0.1, 0.04, 0.35, 0.01, 1400.0, 6.0)


func _make_explosion(s: Synth) -> void:
	s.length(1.6)
	s.drive = 2.6
	s.noise(0.0, 0.04, 0.8, 0.01, 9000.0, 4000.0, 0.0003, 1500.0)
	s.noise(0.0, 1.0, 1.0, 0.26, 6500.0, 140.0, 0.0005)
	s.noise(0.0, 1.1, 0.75, 0.5, 520.0, 75.0)
	s.tone(0.0, 0.9, 1.0, 110.0, 27.0, 0.3)
	s.reverb(0.35, 0.9, 1800.0)


func _make_sledge_swing(s: Synth) -> void:
	s.length(0.22)
	s.noise(0.0, 0.2, 1.0, 0.07, 500.0, 2800.0, 0.07, 280.0)
	s.noise(0.02, 0.18, 0.4, 0.06, 1500.0, 5000.0, 0.08, 1200.0)


func _make_sledge_hit(s: Synth) -> void:
	s.length(0.34)
	s.drive = 2.1
	s.tone(0.0, 0.3, 0.8, 155.0, 44.0, 0.09)
	s.noise(0.0, 0.2, 2.0, 0.03, 3600.0, 550.0, 0.0005)
	s.noise(0.008, 0.05, 1.0, 0.008, 9000.0, 5000.0, 0.001, 2200.0)
	s.reverb(0.2, 0.25)


func _make_ricochet(s: Synth) -> void:
	# A bullet smacking stone: a hard tick and a little grit, no whine.
	s.length(0.2)
	s.noise(0.0, 0.03, 1.0, 0.006, 9000.0, 5000.0, 0.0003, 2500.0)
	s.noise(0.0, 0.12, 0.5, 0.025, 4500.0, 1500.0, 0.0005, 900.0)
	s.reverb(0.2, 0.15)


func _make_zombie_hit(s: Synth) -> void:
	s.length(0.11)
	s.drive = 1.3
	s.noise(0.0, 0.1, 2.0, 0.02, 2300.0, 480.0, 0.0005)
	s.tone(0.0, 0.08, 0.35, 150.0, 80.0, 0.024)


func _make_zombie_die(s: Synth) -> void:
	s.length(0.34)
	s.drive = 1.4
	s.noise(0.0, 0.3, 0.9, 0.06, 1900.0, 280.0)
	s.tone(0.0, 0.3, 0.45, 150.0, 56.0, 0.1, Synth.TRIANGLE, 0.004, 26.0, 0.08)
	s.tone(0.0, 0.14, 0.3, 620.0, 190.0, 0.045, Synth.SINE, 0.003, 40.0, 0.15)


func _make_boss_roar(s: Synth) -> void:
	s.length(1.25)
	s.drive = 3.0
	s.tone(0.0, 1.2, 0.8, 74.0, 44.0, 0.6, Synth.SAW, 0.1, 17.0, 0.07)
	s.tone(0.0, 1.2, 0.5, 111.0, 62.0, 0.5, Synth.SAW, 0.12, 13.0, 0.09)
	s.noise(0.0, 1.2, 0.5, 0.5, 950.0, 300.0, 0.1)
	s.lowpass(1500.0)


func _make_gobber_windup(s: Synth) -> void:
	# A wet gargle at the back of the throat, getting louder.
	s.length(0.55)
	s.drive = 1.5
	s.band(0.0, 0.5, 0.7, 0.3, 420.0, 5.0, 0.25)
	s.tone(0.0, 0.5, 0.35, 95.0, 120.0, 0.35, Synth.SAW, 0.2, 24.0, 0.25)
	s.noise(0.0, 0.5, 0.3, 0.3, 1400.0, 1900.0, 0.3, 500.0)
	s.lowpass(2600.0)


func _make_spit(s: Synth) -> void:
	# "Ptoo": a sharp wet pop.
	s.length(0.18)
	s.drive = 1.4
	s.noise(0.0, 0.05, 1.3, 0.012, 5200.0, 1500.0, 0.0005, 700.0)
	s.band(0.0, 0.14, 0.9, 0.04, 760.0, 5.0)
	s.band(0.02, 0.12, 0.4, 0.04, 1500.0, 7.0)


func _make_spit_hit(s: Synth) -> void:
	# A splat.
	s.length(0.2)
	s.noise(0.0, 0.16, 1.2, 0.04, 2400.0, 420.0, 0.001)
	s.band(0.0, 0.12, 0.5, 0.04, 300.0, 3.0)


func _make_chucker_windup(s: Synth) -> void:
	# A deep grunt of effort and stone scraping.
	s.length(0.7)
	s.drive = 2.0
	s.tone(0.0, 0.65, 0.8, 68.0, 92.0, 0.45, Synth.SAW, 0.12, 15.0, 0.06)
	s.band(0.1, 0.5, 0.4, 0.3, 520.0, 2.5, 0.2)
	s.lowpass(1500.0)


func _make_lob_throw(s: Synth) -> void:
	# A heavy thing swung through the air.
	s.length(0.4)
	s.noise(0.0, 0.36, 0.9, 0.16, 500.0, 1700.0, 0.12, 180.0)
	s.band(0.0, 0.3, 0.35, 0.12, 260.0, 2.0, 0.08)


func _make_lob_land(s: Synth) -> void:
	# Stone hitting the ground: a deep thud, a crack, bits rattling away.
	s.length(0.75)
	s.drive = 1.8
	s.band(0.0, 0.3, 1.5, 0.09, 85.0, 2.0)
	s.noise(0.0, 0.1, 1.2, 0.025, 4200.0, 700.0, 0.0005, 150.0)
	s.band(0.0, 0.18, 0.6, 0.05, 430.0, 4.0)
	for i in 5:
		s.band(0.1 + i * 0.08, 0.06, 0.45 - i * 0.07, 0.015, 900.0 + 230.0 * i, 8.0)
	s.reverb(0.2, 0.3, 2000.0)


func _make_gasbag_fuse(s: Synth) -> void:
	# Skin stretching and gas hissing out, rising.
	s.length(0.65)
	s.noise(0.0, 0.62, 0.8, 0.6, 2200.0, 7000.0, 0.5, 1600.0)
	s.band(0.0, 0.6, 0.5, 0.5, 240.0, 6.0, 0.45)


func _make_gas_burst(s: Synth) -> void:
	# A fat wet bang and a hiss of gas after it.
	s.length(0.9)
	s.drive = 2.2
	s.band(0.0, 0.3, 1.6, 0.1, 120.0, 2.0)
	s.noise(0.0, 0.14, 1.5, 0.035, 3600.0, 380.0, 0.0005)
	s.band(0.0, 0.2, 0.7, 0.06, 340.0, 3.0)
	s.noise(0.08, 0.7, 0.45, 0.3, 5200.0, 1800.0, 0.02, 1400.0)
	s.reverb(0.22, 0.4, 2400.0)


func _make_lunger_shriek(s: Synth) -> void:
	# A thin, rasping screech.
	s.length(0.42)
	s.drive = 1.8
	s.band(0.0, 0.38, 1.0, 0.2, 1750.0, 9.0, 0.03)
	s.band(0.0, 0.38, 0.6, 0.2, 2620.0, 9.0, 0.05)
	s.tone(0.0, 0.36, 0.3, 190.0, 150.0, 0.2, Synth.SAW, 0.02, 34.0, 0.3)
	s.noise(0.0, 0.3, 0.3, 0.15, 6000.0, 3000.0, 0.02, 2000.0)


func _make_boss_charge(s: Synth) -> void:
	s.length(0.85)
	s.drive = 2.4
	s.tone(0.0, 0.8, 0.8, 48.0, 150.0, 0.4, Synth.SAW, 0.5, 22.0, 0.05)
	s.noise(0.0, 0.8, 0.45, 0.3, 300.0, 1700.0, 0.55)
	s.lowpass(1900.0)


func _make_player_hurt(s: Synth) -> void:
	s.length(0.32)
	s.drive = 1.8
	s.tone(0.0, 0.28, 0.6, 330.0, 120.0, 0.1, Synth.SAW)
	s.noise(0.0, 0.2, 0.6, 0.04, 3000.0, 700.0)
	s.tone(0.0, 0.3, 0.6, 92.0, 50.0, 0.1)
	s.lowpass(3200.0)


func _make_player_die(s: Synth) -> void:
	s.length(1.1)
	s.drive = 2.2
	s.tone(0.0, 1.0, 0.7, 270.0, 38.0, 0.42, Synth.SAW)
	s.noise(0.0, 1.0, 0.6, 0.35, 2400.0, 160.0)
	s.tone(0.0, 1.0, 0.8, 84.0, 25.0, 0.4)
	s.lowpass(2600.0)


func _make_coin(s: Synth) -> void:
	s.length(0.16)
	s.tone(0.0, 0.06, 0.5, 1318.5, 1318.5, 0.03)
	s.tone(0.045, 0.11, 0.6, 1975.5, 1975.5, 0.05)
	s.tone(0.045, 0.08, 0.15, 3951.0, 3951.0, 0.03)


func _make_pickup_weapon(s: Synth) -> void:
	s.length(0.46)
	var notes := [392.0, 523.3, 659.3, 784.0]
	for i in notes.size():
		s.tone(i * 0.065, 0.2, 0.5, notes[i], notes[i], 0.08, Synth.TRIANGLE)
		s.tone(i * 0.065, 0.12, 0.18, notes[i] * 2.0, notes[i] * 2.0, 0.05, Synth.SQUARE)
	# "chk-chk": the weapon being racked.
	s.noise(0.3, 0.05, 0.5, 0.012, 7000.0, 2500.0, 0.001, 1500.0)
	s.noise(0.37, 0.06, 0.6, 0.015, 6000.0, 2000.0, 0.001, 1200.0)


func _make_weapon_expire(s: Synth) -> void:
	s.length(0.22)
	s.tone(0.0, 0.08, 0.5, 620.0, 400.0, 0.04, Synth.TRIANGLE)
	s.tone(0.09, 0.12, 0.5, 420.0, 240.0, 0.05, Synth.TRIANGLE)
	s.noise(0.0, 0.03, 0.3, 0.008, 6000.0, 3000.0, 0.001, 1500.0)


func _make_medkit(s: Synth) -> void:
	s.length(0.5)
	var notes := [523.3, 659.3, 784.0, 1046.5]
	for i in notes.size():
		s.tone(i * 0.07, 0.28, 0.5, notes[i], notes[i], 0.12)


func _make_crate_spawn(s: Synth) -> void:
	s.length(0.34)
	s.tone(0.0, 0.2, 0.8, 210.0, 78.0, 0.06)
	s.noise(0.0, 0.08, 0.4, 0.02, 2500.0, 600.0)
	s.tone(0.06, 0.26, 0.3, 880.0, 880.0, 0.11)


func _make_second_wind(s: Synth) -> void:
	# A surge: a rising growl, then a boom.
	s.length(0.95)
	s.drive = 2.6
	s.tone(0.0, 0.5, 0.7, 60.0, 250.0, 0.4, Synth.SAW, 0.3)
	s.noise(0.0, 0.5, 0.6, 0.2, 400.0, 4200.0, 0.4)
	s.tone(0.45, 0.5, 1.0, 125.0, 38.0, 0.2)
	s.noise(0.45, 0.5, 0.8, 0.14, 5000.0, 300.0)
	s.lowpass(5000.0)


func _make_wave_start(s: Synth) -> void:
	s.length(0.85)
	s.drive = 1.2
	s.tone(0.0, 0.8, 0.55, 104.0, 110.0, 0.5, Synth.SAW, 0.08)
	s.tone(0.0, 0.8, 0.45, 156.0, 165.0, 0.5, Synth.SAW, 0.08)
	s.tone(0.0, 0.8, 0.3, 208.0, 220.0, 0.4, Synth.TRIANGLE, 0.1)
	s.lowpass(1700.0)


func _make_wave_clear(s: Synth) -> void:
	s.length(0.7)
	var notes := [523.3, 659.3, 784.0, 1046.5]
	for i in notes.size():
		s.tone(i * 0.085, 0.4, 0.5, notes[i], notes[i], 0.18, Synth.TRIANGLE)
		s.tone(i * 0.085, 0.3, 0.2, notes[i] * 0.5, notes[i] * 0.5, 0.15)


func _make_game_over(s: Synth) -> void:
	s.length(1.7)
	var notes := [329.6, 261.6, 220.0, 164.8]
	for i in notes.size():
		var hold := 0.9 if i == notes.size() - 1 else 0.3
		s.tone(i * 0.26, hold, 0.5, notes[i], notes[i] * 0.985, hold * 0.6, Synth.TRIANGLE, 0.01)
		s.tone(i * 0.26, hold, 0.3, notes[i] * 0.5, notes[i] * 0.49, hold * 0.6, Synth.SAW, 0.01)
	s.lowpass(2200.0)


# Reload sounds. Every gun uses the same few clicks at its own pitch
# ("reload_pitch" in Config.WEAPONS): high and light for the pistol and SMG,
# low and heavy for the machine gun and the launcher.
func _make_mag_out(s: Synth) -> void:
	# Release catch, then the magazine sliding out.
	s.length(0.14)
	s.noise(0.0, 0.02, 1.0, 0.004, 9000.0, 5000.0, 0.0003, 2500.0)
	s.noise(0.03, 0.09, 0.5, 0.022, 4200.0, 2000.0, 0.002, 1200.0)


func _make_mag_in(s: Synth) -> void:
	# A solid clack as the fresh magazine seats.
	s.length(0.16)
	s.drive = 1.4
	s.noise(0.0, 0.03, 1.3, 0.006, 6000.0, 2500.0, 0.0003, 900.0)
	s.noise(0.0, 0.11, 0.8, 0.022, 2600.0, 900.0, 0.0005, 300.0)
	s.tone(0.0, 0.05, 0.25, 170.0, 125.0, 0.015)


func _make_rack(s: Synth) -> void:
	# "Ch-chk": the slide pulled back and let go.
	s.length(0.26)
	s.drive = 1.5
	s.noise(0.0, 0.05, 1.0, 0.012, 5200.0, 2500.0, 0.0005, 1000.0)
	s.noise(0.08, 0.07, 1.4, 0.014, 6200.0, 2200.0, 0.0003, 800.0)
	s.noise(0.08, 0.16, 0.3, 0.04, 2500.0, 900.0, 0.001, 300.0)


func _make_shell_in(s: Synth) -> void:
	# A shell thumbed into the tube.
	s.length(0.13)
	s.noise(0.0, 0.03, 1.0, 0.007, 5000.0, 2200.0, 0.0005, 800.0)
	s.noise(0.02, 0.09, 0.55, 0.022, 2600.0, 1200.0, 0.001, 500.0)


func _make_hiss(s: Synth) -> void:
	# Gas escaping as a fuel tank is unscrewed, with a metal clank.
	s.length(0.36)
	s.noise(0.0, 0.03, 0.9, 0.007, 5000.0, 2000.0, 0.0005, 700.0)
	s.noise(0.02, 0.33, 1.0, 0.11, 9500.0, 6000.0, 0.01, 3000.0)


func _make_level_up(s: Synth) -> void:
	# A bright rising fanfare with a shimmer on top.
	s.length(1.0)
	var notes := [523.3, 659.3, 784.0, 1046.5, 1318.5]
	for i in notes.size():
		s.tone(i * 0.075, 0.5, 0.5, notes[i], notes[i], 0.2, Synth.TRIANGLE)
		s.tone(i * 0.075, 0.4, 0.2, notes[i] * 2.0, notes[i] * 2.0, 0.14)
	s.tone(0.375, 0.6, 0.35, 1046.5, 1046.5, 0.3)
	s.tone(0.375, 0.6, 0.3, 1568.0, 1568.0, 0.3)
	s.reverb(0.3, 0.5)


func _make_weapon_level(s: Synth) -> void:
	# A weapon being racked, then two rising notes.
	s.length(0.5)
	s.noise(0.0, 0.04, 0.7, 0.01, 5000.0, 2500.0, 0.0005, 1200.0)
	s.noise(0.07, 0.05, 0.9, 0.012, 4200.0, 2000.0, 0.0005, 900.0)
	s.tone(0.14, 0.2, 0.5, 587.3, 587.3, 0.09, Synth.TRIANGLE)
	s.tone(0.24, 0.26, 0.55, 880.0, 880.0, 0.12, Synth.TRIANGLE)


func _make_crate_hit(s: Synth) -> void:
	# A bullet thumping into wood.
	s.length(0.14)
	s.band(0.0, 0.1, 1.2, 0.03, 340.0, 4.0)
	s.noise(0.0, 0.04, 0.7, 0.01, 3500.0, 1200.0, 0.0005, 500.0)


func _make_crate_break(s: Synth) -> void:
	# Planks cracking apart and clattering down.
	s.length(0.6)
	s.drive = 1.6
	s.noise(0.0, 0.1, 1.4, 0.03, 5000.0, 900.0, 0.0005, 200.0)
	s.band(0.0, 0.2, 1.0, 0.06, 280.0, 3.0)
	for i in 5:
		s.band(0.08 + i * 0.07, 0.05, 0.7 - i * 0.1, 0.015, 700.0 + 160.0 * i, 6.0)
	s.reverb(0.2, 0.3, 2400.0)


func _make_pet_bite(s: Synth) -> void:
	# A short snarl and the snap of teeth.
	s.length(0.16)
	s.drive = 1.6
	s.band(0.0, 0.09, 1.2, 0.03, 520.0, 3.0)
	s.noise(0.0, 0.07, 0.8, 0.02, 2600.0, 900.0, 0.002, 300.0)
	s.noise(0.05, 0.02, 0.9, 0.005, 7000.0, 4000.0, 0.0005, 2500.0)


func _make_pet_call(s: Synth) -> void:
	# Two sharp barks.
	s.length(0.5)
	s.drive = 1.8
	for i in 2:
		var at := i * 0.17
		s.tone(at, 0.11, 0.8, 520.0, 300.0, 0.05, Synth.SAW, 0.004)
		s.band(at, 0.11, 0.9, 0.04, 900.0, 2.5)
	s.lowpass(3500.0)
	s.reverb(0.2, 0.25)


func _make_gear_drop(s: Synth) -> void:
	# The sound every looter listens for: a clear, ringing "ting" as it lands.
	s.length(0.9)
	s.tone(0.0, 0.8, 0.5, 1760.0, 1760.0, 0.28)
	s.tone(0.0, 0.8, 0.3, 2637.0, 2637.0, 0.22)
	s.tone(0.0, 0.5, 0.2, 3520.0, 3520.0, 0.12)
	s.noise(0.0, 0.03, 0.4, 0.008, 9000.0, 5000.0, 0.0005, 3000.0)
	s.reverb(0.35, 0.6, 5000.0)


func _make_gear_pickup(s: Synth) -> void:
	# A buckle being done up, then three quick rising notes.
	s.length(0.6)
	s.noise(0.0, 0.04, 0.6, 0.01, 4500.0, 2200.0, 0.0005, 1000.0)
	var notes := [784.0, 1046.5, 1568.0]
	for i in notes.size():
		s.tone(0.05 + i * 0.07, 0.3, 0.5, notes[i], notes[i], 0.1, Synth.TRIANGLE)
		s.tone(0.05 + i * 0.07, 0.25, 0.2, notes[i] * 2.0, notes[i] * 2.0, 0.08)
	s.reverb(0.25, 0.35)


func _make_chest_open(s: Synth) -> void:
	# A heavy lid thrown back - wood and an iron latch - then coins spilling
	# and a bright chord climbing.
	s.length(1.3)
	s.drive = 1.3
	s.band(0.0, 0.16, 1.2, 0.05, 190.0, 3.0)
	s.noise(0.0, 0.05, 0.7, 0.012, 4200.0, 1500.0, 0.0005, 400.0)
	s.band(0.03, 0.12, 0.6, 0.03, 1250.0, 9.0)
	var notes := [523.3, 659.3, 784.0, 1046.5, 1318.5]
	for i in notes.size():
		s.tone(0.14 + i * 0.06, 0.7, 0.42, notes[i], notes[i], 0.22, Synth.TRIANGLE)
		s.tone(0.14 + i * 0.06, 0.5, 0.16, notes[i] * 2.0, notes[i] * 2.0, 0.14)
	for i in 6:
		s.band(0.2 + i * 0.05, 0.08, 0.3, 0.02, 3800.0 + 500.0 * (i % 3), 16.0)
	s.reverb(0.3, 0.6, 4500.0)


func _make_forge_ok(s: Synth) -> void:
	# Hammer on an anvil, then a bright chord that hangs in the air.
	s.length(1.2)
	s.drive = 1.2
	s.noise(0.0, 0.05, 1.0, 0.012, 6000.0, 2500.0, 0.0005, 800.0)
	s.band(0.0, 0.5, 0.8, 0.14, 2100.0, 14.0)
	s.band(0.0, 0.4, 0.5, 0.1, 3350.0, 14.0)
	var notes := [523.3, 659.3, 784.0, 1046.5]
	for i in notes.size():
		s.tone(0.12 + i * 0.05, 0.9, 0.4, notes[i], notes[i], 0.35, Synth.TRIANGLE)
	s.tone(0.3, 0.8, 0.25, 2093.0, 2093.0, 0.3)
	s.reverb(0.35, 0.7)


func _make_forge_fail(s: Synth) -> void:
	# The hammer lands wrong: a dull clank and a falling pair of notes.
	s.length(0.7)
	s.noise(0.0, 0.06, 1.0, 0.015, 3000.0, 900.0, 0.0005, 300.0)
	s.band(0.0, 0.25, 0.7, 0.06, 620.0, 8.0)
	s.tone(0.12, 0.25, 0.45, 330.0, 311.0, 0.1, Synth.TRIANGLE)
	s.tone(0.3, 0.35, 0.45, 247.0, 220.0, 0.14, Synth.TRIANGLE)
	s.lowpass(2600.0)


func _make_forge_break(s: Synth) -> void:
	# Metal cracking apart, pieces skittering away, a low groan underneath.
	s.length(1.0)
	s.drive = 1.8
	s.noise(0.0, 0.08, 1.4, 0.02, 7000.0, 1500.0, 0.0005, 400.0)
	s.band(0.0, 0.3, 0.9, 0.07, 480.0, 6.0)
	for i in 5:
		s.noise(0.1 + i * 0.07, 0.03, 0.5 - i * 0.07, 0.008, 8000.0, 4000.0, 0.0005, 2500.0)
	s.tone(0.05, 0.7, 0.6, 110.0, 55.0, 0.25, Synth.TRIANGLE)
	s.reverb(0.3, 0.5, 2200.0)


func _make_dodge(s: Synth) -> void:
	# A quick rush of air.
	s.length(0.2)
	s.noise(0.0, 0.18, 1.0, 0.05, 1200.0, 5000.0, 0.05, 700.0)


func _make_crit(s: Synth) -> void:
	# A sharp, bright snap on top of the normal hit.
	s.length(0.12)
	s.noise(0.0, 0.03, 1.0, 0.005, 12000.0, 7000.0, 0.0003, 3500.0)
	s.noise(0.0, 0.1, 0.5, 0.02, 7000.0, 3000.0, 0.0005, 2000.0)


func _make_ui_move(s: Synth) -> void:
	s.length(0.05)
	s.tone(0.0, 0.045, 0.5, 660.0, 700.0, 0.015, Synth.TRIANGLE)


func _make_ui_click(s: Synth) -> void:
	s.length(0.09)
	s.tone(0.0, 0.08, 0.6, 880.0, 990.0, 0.03, Synth.TRIANGLE)
	s.noise(0.0, 0.02, 0.3, 0.005, 6000.0, 3000.0, 0.001, 1500.0)


func _make_ui_buy(s: Synth) -> void:
	s.length(0.4)
	var notes := [987.8, 1318.5, 1975.5]
	for i in notes.size():
		s.tone(i * 0.06, 0.25, 0.5, notes[i], notes[i], 0.09)
	s.noise(0.0, 0.03, 0.25, 0.008, 8000.0, 4000.0, 0.001, 2500.0)


func _make_ui_deny(s: Synth) -> void:
	s.length(0.22)
	s.tone(0.0, 0.08, 0.5, 150.0, 140.0, 0.05, Synth.SQUARE)
	s.tone(0.11, 0.1, 0.5, 130.0, 118.0, 0.06, Synth.SQUARE)
	s.lowpass(1200.0)
