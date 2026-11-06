extends TestCase
## The device benchmark (tech_architecture.md §15), run here in short form so it keeps working.
## The real numbers come from the iPhone and iPad.


func test_airport_fills_to_a_thousand() -> void:
	Benchmark.prepare_airport()
	check(not SaveGame.enabled, "saving is off while the benchmark runs")
	for i in 30:
		Benchmark.top_up(100)
		sim_seconds(1.0)
	var count := Airport.passenger_flow.passengers.size()
	check(count >= 900, "about 1,000 passengers in the airport (%d)" % count)
	var started := Time.get_ticks_usec()
	sim_seconds(10.0)
	print("INFO simulation step with %d passengers: %.3f ms (Mac)" % [
		Airport.passenger_flow.passengers.size(), (Time.get_ticks_usec() - started) / 1000.0 / 100.0])


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
	for part in ["Top-down", "First person", "Work per frame", "Heartbeat", "Memory", "Result:"]:
		check(benchmark.report.contains(part), "the report shows %s" % part)
	check(benchmark.report.contains("PASS") or benchmark.report.contains("FAIL"), "judged against the budget")
	check(main.current_view == main.View.MANAGER, "the second run is in first person")
	check(benchmark.find_child("CloseButton", true, false) != null, "the results can be closed")


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
