# Source me: `source env.sh`. Gives the closed-loop docs their paths as
# variables, so commands copied out of CLOSED_LOOP_EVAL.md stop hardcoding
# /data/home/xiangyu.gao.
export LAB_ROOT="${LAB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

export FLASHDREAMS="$LAB_ROOT/flashdreams"
export COSMOS="$LAB_ROOT/cosmos-transfer2.5"
export QWEN_DRIVE="$LAB_ROOT/qwen-drive"
export OMNI_DREAMS="$LAB_ROOT/omni-dreams"

# The `dev` worktree, when one exists. Work happens here, not in $FLASHDREAMS,
# because each carries its own venv (see README.md).
[ -d "$LAB_ROOT/flashdreams-dev-v2" ] \
  && export FLASHDREAMS_DEV="$LAB_ROOT/flashdreams-dev-v2" \
  || export FLASHDREAMS_DEV="$FLASHDREAMS"

# ~/.bashrc returns early for non-interactive shells, so the token has to be
# pulled out explicitly -- scripts and agents never inherit it otherwise.
if [ -z "${HF_TOKEN:-}" ] && [ -r "$HOME/.bashrc" ]; then
  export HF_TOKEN=$(grep -oP '(?<=export HF_TOKEN=).*' "$HOME/.bashrc" | head -1)
fi

# Deliberately NOT set here: CUDA_HOME / PATH / LD_LIBRARY_PATH. They must point
# into the venv of the checkout you are running from, and getting that wrong
# produces a confusing libcudart error rather than a clean failure. Set them per
# shell as CLOSED_LOOP_EVAL.md section 0 shows.
