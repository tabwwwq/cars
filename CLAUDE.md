# CLAUDE.md — Cars (Roblox car game)

The user writes in Russian — answer in Russian. Code, comments and commit messages
are in English; player-facing text lives in `src/shared/Strings.luau` (ru + en).

## What this is

A complete Roblox car game written as Rojo-style Luau source:
procedural cars (`CarBuilder` + data in `CarCatalog`), a substepped raycast vehicle
simulation (`CarPhysics`), a generated world (terrain, roads, city, plaza, stunt park,
drift arena, 4 race tracks), races with medals, economy, garage (paint/tuning) and
session-locked DataStore saves.

## Car-service mode

The main game loop besides driving. Data and balance: `src/shared/ServiceConfig.luau`
(levels/XP, vehicle tiers bikes -> buses, services and their hands-on steps, upgrades,
staff, timing). Vehicles that are not cars + workers: `src/shared/ServiceModels.luau`
(same conventions as CarBuilder, anchored `Root` at the ground origin; `weldToRoot`).
Plots: `WorldLayout.ServicePlots` (plot space: +Z faces the west street) built by
`World/ServicePlots.luau`. Server: `Systems/Service.luau` (one plot per player, customers,
orders, bays, step validation with a minimum time per step, staff, upgrades; requests
`ServiceTake/Work/Step/Leave/Dismiss/Buy/Home/Tutorial`, events `ServiceState`,
`ServiceEvent`). Client: `Controllers/Service.luau` (rail of big buttons, orders/business
windows, result and level-up cards, prompts), `Controllers/Workshop.luau` (the minigame:
spots placed by raycasts, brushing, camera orbit), `Controllers/ServiceFX.luau`
(animates paths set by the server — see `Util/Path.luau`; the server never moves models
per frame). Profile field `service` (v3). Add a vehicle: a builder + `ServiceModels.List`
entry, then list its id in a tier. Add a step: `ServiceConfig.Steps` + a service's `steps`
+ `STEP_FLOW`/`LOOK`/tool in `Workshop.luau` + `Step_*`/`StepHint_*` strings.

## Commands

```bash
tools/test.sh            # Luau test suite outside Roblox (builds tools/luau-runner with cargo once)
tools/test.sh physics    # one spec file (cars | physics | server | client | service)
tools/build.sh           # rojo build -> build/CarsGame.rbxlx (place) + build/CarsMode.rbxmx (installer model)
tools/render.sh          # docs/cars.png, service.png, service_plot.png, map.png from the test dumps in tests/out/
selene src && stylua --check src tests
python3 tools/check_api.py <Full-API-Dump.json> src   # class/property/method/enum names vs the real Roblox API
```

The API dump is at
`https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json`
(CI downloads it). Add `-- api-ok` to a line to silence an intentional fallback.

Always run `tools/test.sh`, `selene src`, `stylua src tests`, the API check and `tools/build.sh` before
committing, and commit the rebuilt `build/` files (the user opens them directly in Studio).

## Layout (default.project.json)

| Source | In Roblox | Contents |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage.CarsShared` | Config, CarCatalog, CarBuilder, CarPhysics, Paints, Strings, Tracks, WorldLayout, Net, Types, Util/* |
| `src/server` | `ServerScriptService.CarsServer` (Script) | `init.server.luau` bootstrap, `Systems/*` (one module per system), `World/*` (map builders) |
| `src/client` | `StarterPlayerScripts.CarsClient` (LocalScript) | `init.client.luau`, `ClientState`, `Controllers/*`, `UI/Kit` |
| `assets` | `ReplicatedStorage.CarsAssets` | optional template car bodies (`Cars/<Name>`) |

Bootstraps: every module in `Systems/` (server) and `Controllers/` (client) may export
`init()` (synchronous, runs in the ORDER list) and `start()` (spawned after all inits).
**Unknown modules dropped into those folders are loaded automatically**, after the
listed ones — that is the easiest way to add new features.

Remotes are declared only in `src/shared/Net.luau` (`ServerEvents`, `ClientEvents`,
and the single `Request` RemoteFunction routed by action name with `Net.handle`).
Every client call is rate limited; handlers validate arguments themselves.

## Conventions that matter

- Car space: y = 0 is the ground, **front is −Z**, +X is right. Steering input +1 = right.
- `WedgePart`: full face at local +Z, slope rises from −Z (low) to +Z (high).
  `CarBuilder.wedge(..., risingToRear)` and `World/Build.wedge` rely on this.
- Cylinders have their axis along local X.
- Parts are limited to 2048 studs per axis (split long things).
- Car model: `Chassis` is the only part with mass (RootPriority 127); every other part
  is Massless and welded to it. Wheels are `Wheel_<i>` parts joined with a Motor6D
  `Axle`; the client animates `Axle.Transform`. Wheel/physics data is stored as
  attributes on the wheel parts (`Mount`, `Radius`, `Steer`, `Drive`, `StaticLen`) and
  effective stats as attributes on the model (`MaxSpeed`, `Accel`, ...), written by the
  server (`CarPhysics.writeStats`).
- Collision groups: `Cars`, `Players`, `WheelRays` (rays only hit the world). Registered
  in `Vehicles.init`.
- The **owner's client simulates its car** (network owner) in `Controllers/Drive`;
  `VehicleFX` animates other players' cars locally. The server never applies forces.
- Economy, races and rewards are computed on the server from replicated positions
  with sanity caps (never trust the client).
- Saves: only `Systems/PlayerData` touches DataStores. Add new profile fields in
  `defaultProfile()` + `reconcile()`; bump `CURRENT_VERSION` and add a migration when
  changing the shape.
- World: built at server start by `Systems/World` (or baked in Studio:
  `require(game.ServerScriptService.CarsServer.Systems.World).bake()`). Bump
  `World.VERSION` when the layout changes so baked maps are rebuilt.

## Testing without Studio

`tests/harness/roblox.luau` mocks the Roblox API (Vector3/CFrame math is exact,
Instances are property bags, DataStores are in memory). `tests/harness/carsim.luau`
is a small rigid-body simulator used to drive every car through settle / accelerate /
brake / corner / slalom / drift / slope / jump / FPS-independence scenarios.
When changing `CarPhysics` or car stats, run `tools/test.sh physics`.
`tests/server.spec.luau` also builds the whole map and fails if anything solid stands
on a road, street, the circuit or the dirt trail — keep it green when moving things.
For visual checks of car shapes run the tests, then `python3 tools/render_cars.py
tests/out/cars.json /tmp/out.png <id,id>` and look at the image.

## Merging work from the user's PC

The user has earlier car work on their PC (made with Claude Code there) that is not in
this repo yet. When asked to bring it in:

1. Look at what exists on the PC (scripts, `.rbxl`/`.rbxm` files, models, notes).
2. Luau scripts: convert them into modules under the matching folder —
   server logic → `src/server/Systems/<Name>.luau` (export `init`/`start`),
   client UI/effects → `src/client/Controllers/<Name>.luau`,
   shared data → `src/shared/`. Replace `_G`/loose Scripts with requires.
   Use `Net.handle` / `Net.ServerEvents` instead of creating remotes ad hoc.
3. Car models made in Studio: export them as `.rbxm` into `assets/Cars/` (or keep them
   in the place under `ReplicatedStorage.CarsAssets.Cars`) and add catalog entries with
   `customModel = "<ModelName>"` — wheels, seats, lights and physics are generated.
4. Their old cars with constraint-based physics should become catalog entries tuned
   through `stats` (maxSpeed, accel, grip, steer, drift, suspension...).
5. Keep both versions working: nothing in the place should be deleted without asking;
   the installer keeps old folders as `<Name>_old`.
6. Run the full checklist above, rebuild `build/`, commit and push.

## Ideas not done yet

- Real engine/horn/siren sounds (only hooks in `Config.Sounds` + `VehicleFX`).
- Multiplayer races with a shared start, ghosts of best laps, police chases.
- More areas (airport, mountain road, harbour) and missions/jobs (taxi, delivery).
- Car service: tuning orders (wheels, spoilers), customer NPCs walking to the board,
  co-op work on a friend's plot, sounds for the tools.
- Gamepasses/Developer products (MarketplaceService) — none yet.
