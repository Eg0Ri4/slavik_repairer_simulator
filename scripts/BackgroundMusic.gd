## BackgroundMusic.gd
## Autoload singleton for quiet background music playback
extends AudioStreamPlayer

var music_folder: String = "res://music/"
var playlist: Array[String] = []

func _ready() -> void:
	# Set quiet volume (0.0 is max, -80.0 is silence)
	volume_db = -18.0 
	
	_load_playlist()
	
	# Automatically play the next track when the current one finishes
	finished.connect(_play_next)
	
	_play_next()

func _load_playlist() -> void:
	var dir = DirAccess.open(music_folder)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				# IMPORTANT: Godot appends .import to audio files upon export.
				# We strip it so load() works correctly in the exported build.
				var clean_name = file_name.replace(".import", "")
				
				if clean_name.ends_with(".ogg") or clean_name.ends_with(".mp3") or clean_name.ends_with(".wav"):
					var path = music_folder + clean_name
					if not playlist.has(path):
						playlist.append(path)
			file_name = dir.get_next()
	
	# Shuffle tracks for random playback
	playlist.shuffle()

func _play_next() -> void:
	if playlist.is_empty():
		push_warning("BackgroundMusic: No music found in " + music_folder)
		return
	
	# Take the first track and move it to the end of the array (infinite loop)
	var track_path = playlist.pop_front()
	playlist.append(track_path)
	
	var audio_stream = load(track_path) as AudioStream
	if audio_stream:
		stream = audio_stream
		play()
