extends TestCase
## Frame-rate cap (tech_architecture.md §15): iPhone and iPad run at most 60 frames per second,
## even on 120 Hz screens. It saves battery and heat, and the performance budget assumes 60 fps.
## The cap is a mobile-only project setting, so tests on the Mac still run at full speed.


func test_mobile_is_capped_at_60_fps() -> void:
	check_eq(ProjectSettings.get_setting("application/run/max_fps.mobile"), 60, "iPhone and iPad: at most 60 fps")


func test_desktop_is_not_capped() -> void:
	check_eq(ProjectSettings.get_setting("application/run/max_fps"), 0, "the Mac (tests, editor) has no cap")
	if not OS.has_feature("mobile"):
		check_eq(Engine.max_fps, 0, "and this machine runs without a cap")
