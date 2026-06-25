# Study template

Copy this folder to start a new study:

```
cp -r studies/_template studies/my-study-name
```

Then edit:

1. `lakefile.toml` — package name, roots, dlftk `rev` when frozen
2. `README.md` — question, models, results
3. Rename `StudyTemplate.lean` → `StudyMyStudyName.lean` and update `lakefile.toml`
4. Add claim modules; select models via `import DLFTK...` lines

See `docs/ARCHITECTURE.md` for the full framework design.
