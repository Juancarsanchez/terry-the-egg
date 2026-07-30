class_name AudioManager
extends Node

var player: AudioStreamPlayer


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = -18.0
	add_child(player)


func play_tone(kind: String = "symbol") -> void:
	var frequency := 560.0
	var second_frequency := 840.0
	var duration := 0.11
	match kind:
		"hatch":
			frequency = 660.0
			second_frequency = 990.0
			duration = 0.28
		"talk":
			frequency = 420.0
			second_frequency = 630.0
			duration = 0.13
		"action":
			frequency = 590.0
			second_frequency = 885.0
		"wrong":
			frequency = 260.0
			second_frequency = 390.0
			duration = 0.16

	var sample_rate := 22050
	var sample_count := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for i in sample_count:
		var progress := float(i) / float(sample_count)
		var attack := minf(1.0, progress / 0.08)
		var release := pow(1.0 - progress, 2.4)
		var envelope := attack * release
		var time := float(i) / float(sample_rate)
		var wave := sin(TAU * frequency * time)
		wave += sin(TAU * second_frequency * time) * 0.18
		wave += sin(TAU * frequency * 0.5 * time) * 0.08
		var value := int(clampf(wave * envelope * 5200.0, -32767.0, 32767.0))
		bytes[i * 2] = value & 0xFF
		bytes[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	player.stream = stream
	player.play()
