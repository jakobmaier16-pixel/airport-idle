extends Node
## Runs every walkthrough test in tests/cases/ and quits with exit code 0 (all passed) or 1.
## Start it with tools/run_tests.sh. Optional: `--only=<file or test name part>`, and
## `--seed=<number>` to run every test with that seed instead of its own (tech_architecture.md §3).
## Each test gets a fixed seed from its name, so a run never depends on luck and a failure can be
## replayed exactly with the line it prints.

const CASES_DIR: String = "res://tests/cases/"


func _ready() -> void:
	# Let the scene tree finish starting up before tests add the game to it.
	await get_tree().process_frame
	# Tests drive the simulation themselves (sim_seconds), so it doesn't also run in real time.
	Airport.set_process(false)
	var only := ""
	var forced_seed := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg.begins_with("--seed="):
			forced_seed = arg.trim_prefix("--seed=").to_int()

	var passed := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at(CASES_DIR)).filter(func(f: String) -> bool: return f.ends_with(".gd"))
	files.sort()
	for file: String in files:
		# A test file that doesn't even load is a failure, not a reason to stop the whole run.
		var script := load(CASES_DIR + file) as GDScript
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL %s" % file.get_basename())
			print("  - %s: the test file does not load (see the script errors above)" % file)
			continue
		var test_case: TestCase = script.new()
		add_child(test_case)
		for method in test_case.get_script().get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			var full_name := "%s.%s" % [file.get_basename(), test_name]
			if not only.is_empty() and not full_name.contains(only):
				continue
			_reset_world()
			var seed_value := forced_seed if forced_seed >= 0 else seed_for(full_name)
			Airport.reseed(seed_value)
			test_case.current_test = full_name
			var failures_before := test_case.failures.size()
			var started := Time.get_ticks_msec()
			await test_case.call(test_name)
			await test_case.cleanup()
			var took := Time.get_ticks_msec() - started
			if test_case.failures.size() == failures_before:
				passed += 1
				print("PASS %s (%d ms)" % [full_name, took])
			else:
				failed += 1
				print("FAIL %s" % full_name)
				for message in test_case.failures.slice(failures_before):
					print("  - " + message)
				print("  - replay: tools/run_tests.sh --only=%s --seed=%d" % [full_name, seed_value])
		test_case.queue_free()

	_reset_world()
	print("RESULT: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


## The fixed seed of a test: the same name always gives the same number.
static func seed_for(test_name: String) -> int:
	return test_name.hash() & 0x7fffffff


func _reset_world() -> void:
	# A bare map: tests build what they need. (A real new game also gets the starting runway;
	# the showcase and the walkthrough have it.)
	Airport.reset(false)
	# No random weather in tests: it would make results depend on luck (design doc §12.2).
	Airport.weather.automatic = false
	Airport.incidents_automatic = false
	TouchGestures._reset()
	TouchGestures.pinch_cancels_drag = false
	TouchGestures.independent_drags = false
	SaveGame.enabled = false
	# Tests may pretend to be a newer build (save migration tests).
	SaveGame.format_version = SaveGame.FORMAT_VERSION
	SaveGame.migrations.clear()
