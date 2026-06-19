---
applyTo: "**/*.drawio, docs/diagrams/**"
description: "Architecture diagram authoring workflow (draw.io + Azure icons)"
---

# Diagram authoring workflow (draw.io + Azure icons)

When generating or updating architecture diagrams for this repository, follow this workflow exactly.

## 1. Source of truth

- Always create and maintain a `.drawio` source file under `docs/diagrams/`.
- File naming convention: lowercase-kebab-case (e.g., `docs/diagrams/medallion-architecture.drawio`, `docs/diagrams/fraud-triage-flow.drawio`).

## 2. Export for GitHub / Pages rendering

- GitHub Markdown and the Jekyll Pages site do not render `.drawio` source directly.
- Always export the diagram to **SVG** (preferred) and optionally **PNG**.
- Export path must match the source filename:
  - `docs/diagrams/<name>.svg`
  - optional: `docs/diagrams/<name>.png`

## 3. Markdown integration

- In `README.md`, `DEPLOYMENT_GUIDE.md`, `docs/index.md`, `docs/session-N.md`, or any `session-N/README.md`, reference the **exported image**, not the `.drawio` file.
- Use: `![<Diagram Title>](docs/diagrams/<name>.svg)` (adjust the relative path for files inside `docs/` or `session-N/`).
- If a diagram is updated, ensure all Markdown references still point to the correct exported file.

## 4. Azure architecture icons

- Use the official **Azure Architecture Icons** / draw.io Azure shape libraries where applicable.
- Prefer Azure product icons for the services in this POC — e.g., **Azure Databricks**, **ADLS Gen2 / Storage**, **Microsoft Entra ID**, **Azure Key Vault** — and Databricks workload marks for Unity Catalog, DLT/Lakeflow Pipelines, Mosaic AI, Genie, and Databricks Apps where available.
- Do not substitute a generic icon when an Azure- or Databricks-specific icon exists.

## 5. Consistency and quality

- Keep visual style consistent across diagrams (font, color palette, arrow style, spacing).
- Represent the medallion flow left-to-right or top-to-bottom: Sources → Bronze → Silver → Gold → ML/Serving/BI, with Governance as a cross-cutting concern.
- Include a title and a legend when non-obvious symbols are used.
- Keep labels concise and service names accurate.

## 6. Change handling

- For any diagram change, update:
  - the `.drawio` source file
  - the exported `.svg` (and `.png` if present)
  - any affected Markdown references
- In commit/PR summaries, explicitly mention the diagram source and exported assets updated.

## 7. If tooling/export is unavailable in the current environment

- Still create/update the `.drawio` source.
- Clearly state that the export files (`.svg` / `.png`) must be generated in the VS Code draw.io integration or diagrams.net before merge.
