# Purchasing Log — Processing Procedure

Instructions for the agent. Load this file when there are new documents to process.
Do not load this file routinely — only when a purchase event needs to be recorded.

---

## Trigger

The user drops one or more documents (PDF, image, etc.) into `inbox/`
and asks the agent to process them and update the log.

## Steps

1. **Read the purchasing documents** in `inbox/` (receipts, invoices, customs
   forms). `inbox/` is a shared drop zone — skip `.gitkeep` and any files that
   are not purchasing-related (leave those for their own handling).

2. **Extract the following facts** from the documents. Ignore or redact anything
   else — do not record PII:
   - Date(s): order placed, invoice issued, shipped, delivered, customs cleared
   - Vendor name and country
   - Invoice / order / airwaybill / tracking numbers (these are not PII)
   - Line items: category, description, order number, quantity, unit price, total
   - Order-level costs: shipping, discounts, taxes (type and rate), grand total
   - Currency (record both invoiced currencies if dual-quoted)
   - Incoterms (e.g. DDP, DAP, DAF) — note who bears customs responsibility
   - HS codes if declared on commercial invoice
   - Package details if on packing list (weight, dimensions, carton count)
   - Any actionable notes (e.g. file expiry dates, re-order deadlines)

3. **Do not record:**
   - Personal names
   - Street addresses
   - Phone numbers
   - Email addresses
   - Any other personally identifying information

4. **Insert entries into `purchasing/log.md`** in chronological order by date,
   following the existing format. Each distinct event (order, shipment, delivery,
   customs hold, payment, etc.) gets its own `## YYYY-MM-DD · TYPE · Description`
   heading. Use the established category tags: `FAB`, `ASSEMBLY`, `COMPONENTS`,
   `SHIPPING`, `CUSTOMS`, `PAYMENT`.

   **Do not blindly append to the end of the file.** Read all existing section
   headings, find the correct insertion point by date, and insert there. A
   shipment entry dated earlier than a recent order entry must go *before* that
   order, not after it.

5. **Update the Project Total Spend table** near the top of `purchasing/log.md`.
   Sum all grand totals across all ORDER entries. Do not double-count line items
   that are already rolled up into a grand total. If multiple currencies are
   present, record each separately and note the caveat that EUR figures reflect
   the exchange rate at time of invoicing.

6. **Delete the purchasing documents you processed** from `inbox/` after
   recording them (leave `.gitkeep` and any non-purchasing files in place).

## File locations

| File | Purpose |
|---|---|
| `purchasing/log.md` | The canonical chronological record — append here |
| `inbox/` | Drop zone for unprocessed documents — gitignored, never committed |
| `project_management/agent_workflow_scripts/purchasing.md` | This file |
