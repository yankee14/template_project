# Mechanical

One directory per mechanical item, usually a FreeCAD project.

Mechanical requirements live in `project_management/mechanical.yaml` (prefix
MECH); design decisions (material, fit, fastening, tolerances) go in
`project_management/DESIGN.md`. FreeCAD backup/lock files (`*.FCBak`,
`*.FCStd[0-9]`, `*.FC.lock`) are gitignored; the `.FCStd` source is committed.
