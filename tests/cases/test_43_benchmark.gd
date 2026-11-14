extends TestCase
## The device benchmark (tech_architecture.md §15), run here in short form so it keeps working.
## The real numbers come from the iPhone and iPad.


func test_benchmark_airport_has_planes_on_the_move() -> void:
	Benchmark.prepare_airport()
	check(not SaveGame.enabled, "saving is off while the benchmark runs")
	check(Airport.schedule.flights.size() >= 4, "flights are planned")
	sim_seconds(120.0)
	check(Benchmark.planes_active() >= 1, "planes are on the move (%d)" % Benchmark.planes_active())
	var started := Time.get_ticks_usec()
	sim_seconds(10.0)
	print("INFO simulation step with %d planes active: %.3f ms (Mac)" % [
		Benchmark.planes_active(), (Time.get_ticks_usec() - started) / 1000.0 / 100.0])


# The benchmark airport on a map of `size` cells: the best (lowest) milliseconds per simulation step
# over a few short runs, and the milliseconds one layout change (a walkway cell painted and removed)
# takes. Both are noisy on a shared machine, so the best of a few runs is used.
func _measure(size: Vector2i) -> Dictionary:
	Airport.reseed(Benchmark.SEED)
	ShowcaseAirport.build(180.0, size)
	for i in int(2400.0 / Airport.SIM_STEP):
		if Airport.schedule.flights.size() >= 4:
			break
		Airport.step(Airport.SIM_STEP)
	sim_seconds(60.0)
	var best_step := INF
	for run in 5:
		var started := Time.get_ticks_usec()
		sim_seconds(5.0)
		best_step = minf(best_step, (Time.get_ticks_usec() - started) / 1000.0 / 50.0)
	var best_layout := INF
	var spot: Array[Vector2i] = [MapAnchor.cell(Vector2i(5, 5), Airport.grid.size)]
	for run in 5:
		var started := Time.get_ticks_usec()
		Airport.paint_walkway(spot, true)
		Airport.paint_walkway(spot, false)
		best_layout = minf(best_layout, (Time.get_ticks_usec() - started) / 1000.0 / 2.0)
	return {"flights": Airport.schedule.flights.size(), "step_ms": best_step, "layout_ms": best_layout}


# The step costs the same on the big map as on the small one: the simulation only touches used
# cells. A generous ratio (and the best of several runs) keeps it from flaking on a busy machine.
func test_big_map_step_is_not_slower() -> void:
	# Two rounds in turn, the best of each size: a busy machine slows a whole run, not one size.
	var small := _measure(SMALL_MAP)
	var big := _measure(AirportWorld.MAP_SIZE_CELLS)
	var again_big := _measure(AirportWorld.MAP_SIZE_CELLS)
	var again_small := _measure(SMALL_MAP)
	for key in ["step_ms", "layout_ms"]:
		small[key] = minf(small[key], again_small[key])
		big[key] = minf(big[key], again_big[key])
	print("INFO step with %d flights: %dx%d %.3f ms, %dx%d %.3f ms; layout change: %.2f ms vs %.2f ms" % [
		big["flights"], SMALL_MAP.x, SMALL_MAP.y, small["step_ms"], AirportWorld.MAP_SIZE_CELLS.x, AirportWorld.MAP_SIZE_CELLS.y, big["step_ms"], small["layout_ms"], big["layout_ms"]])
	check(big["flights"] >= 1 and small["flights"] >= 1, "both airports have flights (%d, %d)" % [small["flights"], big["flights"]])
	check(big["step_ms"] <= small["step_ms"] * 1.2 + 0.2, "a step on the big map is at most 1.2 x the small one plus 0.2 ms of slack (%.3f vs %.3f ms)" % [big["step_ms"], small["step_ms"]])
	check(big["layout_ms"] <= small["layout_ms"] * 3.0 + 20.0, "a layout change on the big map is not much slower (%.2f vs %.2f ms)" % [big["layout_ms"], small["layout_ms"]])


func test_benchmark_runs_and_reports() -> void:
	Benchmark.prepare_airport()
	await start_game()
	var benchmark := Benchmark.new()
	benchmark.main = main
	benchmark.fill_seconds = 3.0
	benchmark.phase_seconds = 1.0
	main.add_child(benchmark)
	# The benchmark measures the game running in real time.
	Airport.set_process(true)
	var started := Time.get_ticks_msec()
	while benchmark.phase != Benchmark.Phase.DONE and Time.get_ticks_msec() - started < 30000:
		await frames(1)
	Airport.set_process(false)
	check_eq(benchmark.phase, Benchmark.Phase.DONE, "the benchmark finished")
	# Without a screen, frame and graphics times read 0 here; heartbeats are real on every machine.
	for run_phase in [Benchmark.Phase.TOP_DOWN, Benchmark.Phase.FIRST_PERSON]:
		check(benchmark.heartbeat_samples(run_phase) > 0, "heartbeats were measured in run %d" % run_phase)
	check(not benchmark.report.contains("Heartbeat           avg 0.0 ms"), "the heartbeat numbers are real")
	for part in ["Top-down", "First person", "planes on average", "Work per frame", "Heartbeat", "Memory", "Result:"]:
		check(benchmark.report.contains(part), "the report shows %s" % part)
	check(benchmark.report.contains("PASS") or benchmark.report.contains("FAIL"), "judged against the budget")
	check(main.current_view == main.View.MANAGER, "the second run is in first person")
	check(benchmark.find_child("CloseButton", true, false) != null, "the results can be closed")
	# Without a screen there is no graphics time: the report says so instead of showing 0.0 ms.
	check(benchmark.report.contains("not measured on this device"), "an unmeasured graphics time is named as such")
	var results := benchmark.find_child("Results", true, false) as PanelContainer
	var background := results.get_theme_stylebox("panel") as StyleBoxFlat
	check(background != null and background.bg_color.a == 1.0, "the results screen has a solid background")
	check(benchmark.report.contains("Frame cap"), "the report shows the frame cap")


func test_percentile() -> void:
	var values := PackedFloat32Array()
	for i in range(100, 0, -1):
		values.append(i)
	check_eq(Benchmark.percentile(values, 0.95), 95.0, "95 % of the values are at most 95")
	check_eq(Benchmark.percentile(PackedFloat32Array(), 0.95), 0.0, "no values: 0")


func test_bench_button_needs_two_taps() -> void:
	await start_game()
	await open_build_view()
	var button := ui("BuildMenu/PaintButtons/BenchButton") as Button
	check(button.visible, "the Bench button exists in test builds")
	await press(button)
	check_eq(button.text, "Tap again", "the first tap only arms it")
	check(not Benchmark.pending, "nothing started yet")
