class_name StationUpgrade
extends Resource
## One upgrade level of a station (design doc §7.8). Listed in BuildingType.upgrades:
## the first entry upgrades level 1 to 2, the second level 2 to 3, and so on.

## Shown on the Upgrade button, e.g. "+1 counter".
@export var title: String
@export var cost: float = 0.0
## Added to the station's running costs once the upgrade is done (euros per minute).
@export var extra_running_cost_per_minute: float = 0.0
## Extra counters / lanes.
@export var extra_slots: int = 0
## Multiplies the time per passenger (0.75 = 25 % faster).
@export var service_time_factor: float = 1.0
## 0 = instant (small upgrade). Otherwise seconds of construction (big upgrade, design doc §5).
@export var build_seconds: float = 0.0
