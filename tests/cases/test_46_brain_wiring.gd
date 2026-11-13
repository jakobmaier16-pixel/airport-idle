extends TestCase
## The simulation classes get the airport through a typed field, not through the global
## autoload (tech_architecture.md §17, step 2a).


func test_simulation_objects_know_their_airport() -> void:
	Airport.reset()
	check(Airport.passenger_flow.world == Airport, "passenger flow knows the airport")
	check(Airport.passenger_flow.schedule.world == Airport, "flight schedule knows the airport")
	check(Airport.goals.world == Airport, "goals know the airport")
	Airport.reset(false)
	check(Airport.passenger_flow.world == Airport, "still wired after a second reset")
	check(Airport.passenger_flow.schedule.world == Airport, "schedule still wired after a second reset")
