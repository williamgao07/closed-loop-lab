# Closed-loop evaluation: a guide for new contributors

`CLOSED_LOOP_EVAL.md` in the flashdreams checkout is the command reference — 1300
lines, organised by task, correct, and not designed to be read front to back.
This is the other thing: what the system *is*, the order to try things in, and
how to tell a real result from an artifact of the setup. Read this once, then
live in that one.

## What "closed loop" means here

A world model renders what a camera would have seen. A policy looks at those
rendered pixels and plans where to drive. That plan moves the ego. The world
model re-renders from the new pose. Repeat.

```
  scene (map + actors) ─┐
                        ▼
          ego pose ─► world model ─► frames ─► policy ─► plan ─┐
              ▲                                                │
              └────────────────────────────────────────────────┘
```

The loop is what makes this different from replaying a recording. Once the
policy chooses differently from the logged driver, the recording stops being the
right answer — the car is somewhere that was never filmed. That is the entire
point (you can ask "what if the truck had cut in 2 s earlier?"), and it is also
why most of the obvious metrics mislead. See "Reading results" below.

**Open loop**, by contrast, replays the logged ego path and only renders. Useful,
and much cheaper to debug, because it separates video quality from planning.

## The pieces

| Piece | Repo | What it does |
|---|---|---|
| Harness | `flashdreams` — `integrations_v2/omnidreams/impl/closed_loop/` | Runs the loop, scores it |
| Scene ingest | `flashdreams` — `impl/scene_sources/` | Turns a recording into a source-agnostic IR |
| World model | `flashdreams` — served over gRPC | Renders frames from pose + actors |
| Policy | `qwen-drive` — `serve_policy.py` | Plans from frames, over HTTP |
| Multi-view generator | `cosmos-transfer2.5` | Alternative backend, 7 cameras, much slower |

Three seams, each swappable on its own: **scene** (`scene_sources`),
**generator** (`WorldGenerator`), **planner** (`PlannerAdapter`). If you are
adding something, you almost certainly want to implement one of those three
interfaces rather than touch the loop.

The policy runs in a **separate process with its own venv**, and that is forced,
not stylistic: Qwen-Drive needs transformers 5.14 and torch 2.8/cu128 against the
harness's 5.12 and 2.12/cu130, and its modeling code isn't on Hugging Face at all
— only weights — so there is no `trust_remote_code` shortcut. Hence an HTTP
contract between them.

## Start here, in this order

Each rung proves one thing and costs more than the last. Skipping ahead is how
people spend a day debugging the wrong layer.

### 1. HDMap-only — does the geometry line up?

Renders the conditioning HDMap and skips diffusion. Nearly free on GPU.
`--hdmap-only`, command in **§9a**.

Then eyeball the output against the real camera frames. Lane markings should sit
on the real lanes. This is the only cheap way to tell a wrong coordinate
conversion from a model that ignored its conditioning — and the conventions here
fail *silently* when wrong (FLU world frame, x forward / y left / z up; µs int64
timestamps; `(x,y,z,w)` quaternions; boxes as length/width/height). Get this
green before anything else.

### 2. Open loop with the logged path — is the video any good?

`--adapter logged-trajectory`, command in **§4b**. Replays the recorded ego path,
so ADE/FDE are 0.000 by construction and anything ugly in the frames is the
generator. This is your video-quality control, and the baseline every closed-loop
run gets compared against.

### 3. Closed loop with the *fake* policy — is the plumbing right?

```bash
python fake_policy_service.py --port 8710 --speed-mps 21 --curvature 0.0
```

No model, no GPU, no weights, and it asserts the request shape, so a contract
mismatch surfaces as an assertion instead of as a bad video. Then run §10c
pointed at it.

Do this before touching the real model. A policy whose intent you know exactly
means anything strange in the numbers is the harness, not the model — which is
otherwise very hard to tell apart from a video. Four real bugs were found this
way (§12), including an ego that froze for 0.1 s at every chunk boundary and read
as "12% slower than commanded".

### 4. Closed loop with the real model

§10a to install, §10b to serve on GPU 7, §10c to run. Expect ~1.15 s planning
plus ~0.51 s rendering per chunk, after a ~53 s first-call warm-up.

One install note that will otherwise eat an afternoon: `flash-attn==2.8.3` and
`causal-conv1d` **do not build on this box** (their pins are CUDA 12.8, the box is
CUDA 13; you get `NameError: name 'bare_metal_version' is not defined`). Don't
fight the wheel. Install the rest and run `--attn sdpa`; `serve_policy.py` falls
back to it anyway and logs which one ran. It's a speed difference, not a
correctness one.

### 5. Counterfactuals

`impl/scene_sources/edits.py`, **§14**. Spawn an agent that was never logged,
delete logged ones — pure `FleetScene -> FleetScene` rewrites. Python API only;
there's no `--scene-edits` flag yet because the op set is still moving and a
sweep is a `for` loop anyway. **Read the adherence warning below before drawing
any conclusion from these.**

## Reading results

Every run writes `metrics.json` and prints a Markdown summary: distance, speed,
lateral acceleration and curvature, ADE/FDE and lateral divergence, collisions,
distance to the nearest lane line, and planner-vs-generator latency.

Four rules for reading it honestly. Each of these has already caught someone:

- **Trajectory deviation is divergence, not error.** Once the policy chooses
  differently, the recording is no longer ground truth. A large ADE may mean the
  policy drove badly, or that it made a different legitimate choice. The number
  alone cannot tell you which.
- **Collision counts against `--logged-fleet-actors` measure speed matching, not
  safety.** Replayed tracks don't react. The same policy took 10 collisions at
  21.0 m/s and 0 at the recording's 21.8 m/s, with lateral divergence essentially
  unchanged (0.277 → 0.248 m). Real collision testing needs reactive agents,
  which we don't have.
- **Cars in the video are not evidence that actor conditioning worked.** With
  *zero* dynamic actors the model still generates plausible traffic — and
  generates it more cleanly than any run with actors. Traffic here is
  substantially seed-frame and prior driven.
- **A held plan is not a driven plan.** Implausible plans are rejected
  (`--policy-max-speed-mps`, default 40), the last good plan is held, and the
  rejection is counted. Check that count: in one 12-chunk rollout, 8 chunks ran
  on a held plan. The video looks perfectly smooth either way.

## Known limits — what this cannot currently tell you

Please read before designing an experiment around it.

- **The model largely does not paint injected obstacles.** Editing actors is a
  solved plumbing problem and an unsolved *adherence* problem. An injected
  pedestrian or car in the ego's lane reaches the HDMap conditioning correctly
  and is scored by `metrics.py`, but renders as bare asphalt. Verified
  pixel-exact against the matching `--hdmap-only` render. Both obvious
  explanations were tested and refuted: it is not the transport (baking obstacles
  from the scene's own parquet produces the same conditioning image, mean |diff|
  0.61 of 765), and it is not distillation (the non-distilled teacher paints the
  near logged car but leaves the pedestrian's window bare). Adherence is weak and
  scale-dependent, not absent.
- **The policy plans well for only ~4 s.** After the generated scene drifts, it
  starts returning a first waypoint ~16 m ahead instead of ~2 m.
- **The three-view gap.** Qwen-Drive requires exactly three forward views; the
  single-view generator renders one. Both bridges are honest about being bridges:
  `duplicate-front` is plainly out of distribution, `virtual-crop` plans better
  when it plans but rejects just as often. These are *separate* problems from the
  appearance drift above; a multi-view generator would address both.
- **There is no ground-truth RGB video** in the public scene assets — only one
  seed frame per scene. Generated output cannot be scored against reality, only
  inspected.
- **GPUs 6 and 7 only, and they are shared.** A co-tenant appearing *after* the
  server sizes its allocations kills the run mid-rollout with a CUDA OOM that
  surfaces client-side as a gRPC `StatusCode.UNKNOWN`. Check free memory
  immediately before launching, and run rollouts under `nohup` — a foreground
  timeout can kill the process mid-ffmpeg-write and leave a truncated MP4.

## Contributing

- Branch off `dev`, one topic branch per PR. Never commit to `main` in any fork;
  it is a pure upstream mirror.
- Adding a data source, a generator, or a policy? Implement the seam, don't edit
  the loop. `tests/test_closed_loop_isolation.py` enforces that only files under
  `impl/closed_loop/backends/` may import gRPC or the protobuf stubs — and asserts
  the complement too, so it can't pass by nothing using gRPC at all.
- A new map layer is a new mapper, not an IR change. `impl/scene_sources/ir.py`'s
  module docstring is the authoritative contract.
- Re-pin `manifest.tsv` with `./pin.sh` after a run that verifies a new
  combination, and keep `CLOSED_LOOP_EVAL.md` current when commands change.
- Record what you *refuted*, not just what worked. Several entries above are
  negative results, and they are the most expensive thing in this repo to
  rediscover.
