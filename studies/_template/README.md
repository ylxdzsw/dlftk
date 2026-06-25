# Study template

Copy this folder to start a new study:

```
cp -r studies/_template studies/my-study-name
```

Then edit:

1. `study.toml` — id, title, dlftk pin, models/features
2. `README.md` — question, results table
3. `lakefile.toml` — package name and default target
4. Rename `StudyTemplate.lean` → `StudyMyStudyName.lean`
5. Add claim modules and import them from the study root

See `docs/ARCHITECTURE.md` for the full framework design.
