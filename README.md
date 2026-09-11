# closed-loop-lab

Entry point for the closed-loop world-model evaluation work. It owns no model
code — it pins the four repos that do, and records the things that are true of
the setup rather than of any one repo.

Start here, not in a checkout: `CLOSED_LOOP_EVAL.md` assumes an environment that
this sets up.

```bash
git clone git@github.com:williamgao07/closed-loop-lab.git
cd closed-loop-lab
./bootstrap.sh          # clone/verify all four repos at their pinned commits
source env.sh           # $FLASHDREAMS, $QWEN_DRIVE, $COSMOS, $OMNI_DREAMS, $HF_TOKEN
```

The four repos are cloned as **siblings of this one**, not inside it — so the
layout above becomes `work/closed-loop-lab`, `work/flashdreams`,
`work/qwen-drive`, and so on. Override with `LAB_ROOT` if you want them
elsewhere; `bootstrap.sh` and `env.sh` both honour it.

Then follow **`$FLASHDREAMS_DEV/CLOSED_LOOP_EVAL.md` §0** for the per-checkout
CUDA toolchain, and §4 to run the closed-loop client.

## The repos

| repo | role | we patch it? |
|---|---|---|
| `flashdreams` | the world model + the closed-loop harness (`integrations_v2/omnidreams/impl/closed_loop`, `scene_sources`) | yes — `dev` |
| `qwen-drive` | the driving policy, served over HTTP by `serve_policy.py` | yes — `dev` |
| `cosmos-transfer2.5` | multi-view generation, as an alternative backend | yes — `dev` |
| `omni-dreams` | upstream scene/dataset tooling | no — read-only |

Exact URLs and pinned commits live in `manifest.tsv`. After a run that verifies
a new combination, `./pin.sh` re-pins it — the pins are only worth something if
they name commits that were seen working *together*.

## Conventions

- **`main` is a pure mirror of upstream.** Never commit to it, in any fork. That
  keeps `git fetch origin && git merge --ff-only origin/main` working forever and
  keeps any PR back upstream readable.
- **`dev` is the integration branch**, with topic branches off it, one per PR.
- Git identity is set **per repo**, never globally (`bootstrap.sh` does this).

## Documentation that lives elsewhere

Deliberately not duplicated here — it belongs next to the code it describes, and
a copy would rot:

- `$FLASHDREAMS_DEV/CLOSED_LOOP_EVAL.md` — the main runbook. §0 environment,
  §1 GPU/CPU budget, §4 the client, §7 gotchas, §10 closing the loop with
  Qwen-Drive, §11 swapping the generator, §12–14 results.
- `$COSMOS/MULTIVIEW_ON_THIS_BOX.md` — multi-view setup, and why it needs its
  own checkout and venv.

## Things that will waste your afternoon

- **Each checkout needs its own venv, and `CUDA_HOME` must point inside *that*
  one.** The pins genuinely conflict: FlashDreams is on torch 2.12/cu130,
  Qwen-Drive was verified on torch 2.8/cu128, Cosmos pins torch 2.9.1 with a
  cu130 flash-attn wheel. They cannot share an environment. Pointing `CUDA_HOME`
  at the wrong one fails as `OSError: libcudart.so: cannot open shared object
  file`, which does not look like the mistake it is.
- **Two cosmos READMEs under `assets/` are permanently "modified".** They are
  not your edits — the working-tree bytes equal `HEAD`. Upstream prepended a
  banner to files that are git-lfs *pointers*, so the clean filter re-hashes
  them on every diff. Never stage them: it swaps a real README pointer for a
  pointer to the banner text.
- **`assets/**` in cosmos is LFS.** Anything added there, even a 400-byte JSON,
  commits as a pointer. Forks do not share LFS storage with the parent, so the
  first push of a branch uploads every object it references (237 MB, against a
  1 GB personal-account quota).
- **No weights in git.** `Qwen-Drive-1.0-4B/` (~11.7 GB) and the HF datasets
  (`nvidia/omni-dreams-{scenes,models,samples}`) are fetched, and ignored.
- **`uv` writes `.venv/.gitignore` containing `*`**, so venvs self-ignore and
  never appear in `git status`. Do not go looking for why.
- **GPUs 6 and 7 only, and they are shared.** A co-tenant that appears *after*
  the server sizes its allocations kills the run mid-rollout with a CUDA OOM
  that surfaces client-side as a gRPC `StatusCode.UNKNOWN`. Check free memory
  immediately before launching. Cap CPU threads too — `taskset` to NUMA node 1
  (`56-111,168-223`) rather than taking all 224.
