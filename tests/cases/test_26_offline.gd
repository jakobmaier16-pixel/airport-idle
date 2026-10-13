extends TestCase
## Offline income (design doc §5): nothing under 36 hours, then 4 hours of profit once.

const TEST_SAVE: String = "user://test_offline_savegame.json"


func test_short_break_earns_nothing() -> void:
	Airport.economy.average_profit_per_minute = 100.0
	var before := Airport.economy.balance
	check_eq(SaveGame.apply_offline_time(35.0 * 3600.0), 0.0, "35 hours: no bonus")
	check_eq(Airport.economy.balance, before, "money unchanged")


func test_long_break_pays_four_hours_once() -> void:
	Airport.economy.average_profit_per_minute = 100.0
	var before := Airport.economy.balance
	check_eq(SaveGame.apply_offline_time(40.0 * 3600.0), 24000.0, "4 hours × 60 × €100")
	check_eq(Airport.economy.balance, before + 24000.0, "paid")
	check_eq(SaveGame.apply_offline_time(400.0 * 3600.0), 24000.0, "never more than 4 hours, however long")
	SaveGame.welcome_back_bonus = 0.0


func test_losing_airport_gets_no_bonus() -> void:
	Airport.economy.average_profit_per_minute = -50.0
	check_eq(SaveGame.apply_offline_time(48.0 * 3600.0), 0.0, "no bonus, and no loss either")
	SaveGame.welcome_back_bonus = 0.0


func test_average_profit_follows_the_airport() -> void:
	ShowcaseAirport.build(0.0)
	sim_seconds(900)
	check(Airport.economy.average_profit_per_minute > 0.0, "the showcase's long-term profit: %.0f" % Airport.economy.average_profit_per_minute)


func test_welcome_back_after_loading() -> void:
	SaveGame.save_path = TEST_SAVE
	SaveGame.enabled = true
	ShowcaseAirport.build(0.0)
	Airport.economy.average_profit_per_minute = 50.0
	SaveGame.save_now()
	# Pretend the save is two days old.
	var data := JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE)) as Dictionary
	data["saved_at"] = Time.get_unix_time_from_system() - 48.0 * 3600.0
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var balance := float(data["money"])
	SaveGame.load_game()
	check_eq(SaveGame.welcome_back_bonus, 12000.0, "4 hours of €50 per minute")
	check(is_equal_approx(Airport.economy.balance, balance + 12000.0), "paid on loading")
	await start_game()
	check(hud().notice_text().begins_with("Welcome back! You were away 48 hours"), "notice: '%s'" % hud().notice_text())
	SaveGame.reset_game()
	SaveGame.enabled = false
	SaveGame.save_path = "user://savegame.json"
