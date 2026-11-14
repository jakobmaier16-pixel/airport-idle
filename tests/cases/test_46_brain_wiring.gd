extends TestCase
## The simulation classes get the airport through a typed field, not through the global
## autoload (tech_architecture.md §17, step 2a).


func test_simulation_objects_know_their_airport() -> void:
	Airport.reset()
	check(Airport.schedule.world == Airport.brain, "flight schedule knows the airport")
	check(Airport.goals.world == Airport.brain, "goals know the airport")
	Airport.reset(false)
	check(Airport.goals.world == Airport.brain, "goals still wired after a second reset")
	check(Airport.schedule.world == Airport.brain, "schedule still wired after a second reset")
