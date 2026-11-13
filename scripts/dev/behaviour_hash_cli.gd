extends Node
## Command-line entry of tools/behaviour_hash.sh (scene behaviour_hash_cli.tscn): prints the
## behaviour hash and quits.


func _ready() -> void:
	print("BEHAVIOUR_HASH ", BehaviourHash.compute())
	get_tree().quit()
