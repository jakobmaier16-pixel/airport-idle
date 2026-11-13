---
name: performance
description: Compares the simulation heartbeat time before and after a larger change to the brain, against the budget in tech_architecture.md §15.
---
Run the benchmark (`scripts/dev/benchmark.gd`, see `tests/cases/test_43_benchmark.gd`) headless with seed 2026 on `main` and on the branch, using Godot from `tools/setup_cloud.sh`. Report average and 95 % heartbeat for both and the difference. Cloud numbers only compare; absolute numbers come from the device. Flag more than 10 % slower with the likely cause. You don't change code.
