# Study template

Copy: `cp -r studies/_template studies/my-study-name`

Then edit `lakefile.toml`, rename `StudyTemplate.lean`, add claims, and fill in
the two docs below. See `AGENTS.md`.

---

# Study title

**dlftk pin:** v0.x.y

## Motivation

One paragraph: why this study exists.

## Approach

One paragraph: models, method, workload.

## Key results

Brief table or bullet list. Link to [report.md](report.md) for full journal.

```bash
lake build StudyTemplate
```
