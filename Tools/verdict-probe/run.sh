#!/usr/bin/env bash
# Scores the Anchr classification prompt against hand-written observations.
set -uo pipefail
cd "$(dirname "$0")"

PROMPT_HEAD='You judge whether a person is working on their stated task.

You get: their ANCHOR (the task they said they are on), its PARENT CHAIN, the
PROJECT CONTEXT, the OPEN ITEMS of their list, and OBSERVATION — a flattened
accessibility tree of the window that is in front of them right now.

Rules:
- "on_task" means the observation plausibly serves the anchor, including reading,
  research, and tooling that the anchor needs.
- "unclear" means you cannot tell, or the window is too thin to judge. Research
  and reading look like drift; when in doubt use unclear, not off_task.
- "off_task" means the observation clearly serves something other than the anchor
  and the list.
- evidence: one sentence naming what is actually on screen.
- smaller_step: always required, even when on_task. The next, more specific action
  toward the anchor, phrased in the user vocabulary of the list.
Answer with the JSON object only.'

score=0; total=0
for f in cases/case_*.txt; do
  total=$((total+1))
  expected=$(head -1 "$f" | sed 's/^EXPECT: //')
  name=$(sed -n 2p "$f" | sed 's/^NAME: //')
  body=$(tail -n +3 "$f")
  start=$(date +%s)
  codex exec --ephemeral --skip-git-repo-check -s read-only \
    -c model_reasoning_effort=low \
    --output-schema schema.json -o "/tmp/anchr-verdict-$(basename $f).json" \
    "$PROMPT_HEAD

$body" > /dev/null 2>&1
  end=$(date +%s)
  got=$(python3 -c "import json,sys;print(json.load(open('/tmp/anchr-verdict-$(basename $f).json'))['verdict'])" 2>/dev/null || echo ERROR)
  mark="MISS"
  if [ "$got" = "$expected" ]; then mark="ok"; score=$((score+1)); fi
  echo "[$mark] $name  expected=$expected got=$got  $((end-start))s"
  python3 -c "
import json
d=json.load(open('/tmp/anchr-verdict-$(basename $f).json'))
print('      evidence:', d['evidence'])
print('      smaller :', d['smaller_step'])
" 2>/dev/null
done
echo "SCORE: $score / $total"
