extends TestCase
## Seasons (design doc §12.2): they only change demand by route type.


func test_seasons() -> void:
	check_eq(Seasons.season_of(1), Seasons.Season.SPRING, "a new airport starts in spring")
	check_eq(Seasons.season_of(3), Seasons.Season.SUMMER, "two days per season")
	check_eq(Seasons.season_of(7), Seasons.Season.WINTER, "winter on day 7")
	check_eq(Seasons.season_of(9), Seasons.Season.SPRING, "and round again")
	check(Seasons.demand_factor("Holiday", Seasons.Season.SUMMER) > 1.3, "summer holidays")
	check(Seasons.demand_factor("Holiday", Seasons.Season.WINTER) < 0.8, "quiet winter holidays")
	check_eq(Seasons.demand_factor("Unknown", Seasons.Season.WINTER), 1.0, "unknown routes are not affected")


func test_clock_shows_the_season() -> void:
	check_eq(Airport.season(), Seasons.Season.SPRING, "spring on day 1")
	check_eq(Seasons.text(Seasons.Season.WINTER), "Winter", "named for the HUD")
