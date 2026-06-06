# Software

One directory per application. Many are Python.

Per Python app:

- `software/<app>/.venv` — app virtual environment (gitignored).
- `software/<app>/requirements.txt` — pinned deps; update when adding a package.
- `ruff` for lint + format.

Run from the repo root, e.g. `software/<app>/.venv/bin/python -m <app>`. Never
touch system pip. The root `.venv/` is for project-servicing tooling only — not
for any app here.

Software requirements live in `project_management/software.yaml` (prefix SW);
implementation choices (GUI toolkit, config format, libraries) go in
`project_management/DESIGN.md`.
