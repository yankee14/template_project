# Documentation

- `datasheet/` — component datasheets (PDF), for parts selected during
  development. Organize by category/part as convenient.
- `literature/` — application notes and reference literature, typically tied to
  one or more components in `datasheet/`.

Datasheets are committed (they are chosen during design and feed schematic
review). The schematic-review procedure looks here for each BOM part's
datasheet and flags any that are missing.

**Sidecar `.md` per datasheet.** Every datasheet PDF gets a sibling Markdown
file with the same basename (`icm-42688p.pdf` → `icm-42688p.md`), created when
the PDF is filed (even if empty). When you read a datasheet to answer a
question, record in its sidecar only the critical facts that drive a
hardware-design or firmware decision — supply voltages/currents, pinout,
interface/timing limits, package, abs-max — and cite the sibling PDF +
page/table. Anything that does not inform design stays out. A source with no PDF
(vendor-web-only spec) still gets a sidecar; there it *is* the spec sheet — mark
it vendor-claimed and note no PDF is filed.
