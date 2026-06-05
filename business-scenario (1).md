Material Master Governance
with IDOC Distribution
Madhuri  •  SAP MDG Consultant  •  Self-Directed Portfolio Project  •  May 2026
Background
I built this during a career break as a way to stay sharp and go deeper on MDG — an area I wanted to own end-to-end, not just contribute to as a team member.
The business scenario is based on a problem pattern I researched across automotive and discrete manufacturing implementations — inconsistent material master data across multi-plant SAP landscapes is one of the most documented MDG use cases, and I wanted to design a complete solution for it: requirements, configuration, custom ABAP, IDOC integration, and error handling.
Everything was built and tested on a personal SAP sandbox system.

What I Set Out to Solve
Inconsistent Material Descriptions Across Plants
The same raw steel sheet existed in all three plants, but you’d never know it from the data:

Material: Raw Steel Sheet – Grade A2 Plant 1: "STEEL-SHT-A2-RAW"  |  Price: $450/ton Plant 2: "Steel Sheet A2"    |  Price: $445/ton Plant 3: "A2 Steel Raw"      |  Price: $460/ton

This wasn’t a data quality team’s problem — it was a governance gap. There was no single owner, no creation process that enforced standards, and no way to catch this before it went live.

120+ Duplicate Materials, ~$180K in Excess Inventory
When I ran the duplicate analysis, this was the number that got attention. The duplicates had been accumulating for years because each plant created materials independently. Nobody was checking whether a material already existed somewhere else in the landscape.

2–3 Day Material Creation Cycle, Mostly Manual
Material creation required manual entry in each plant system. Errors were common — roughly 25 per month — and there was no approval step, no audit trail, and no way to trace who changed what.

What I Built
I designed and configured a centralized governance solution using SAP MDG 8.0 on ECC 6.0 as the hub, with three receiving plant systems connected via ALE/IDOC (MATMAS message type). The end-to-end flow:

Request (Create/Change)   → BRF+ Validation Rules   → Single-step Workflow Approval   → MDG Activation   → MATMAS IDOC Generation   → ALE Distribution to 3 Plants   → Error Monitoring (Z_MDG_IDOC_ERROR_MONITOR)

Governance Scope
I scoped the solution to cover the material types most prone to inconsistency in manufacturing: ROH (raw materials), HALB (semi-finished), FERT (finished goods), and HAWA (trading goods). Data areas covered included basic data, classification, plant/MRP data, purchasing, and accounting/valuation.

Custom ABAP Development
Three custom objects I wrote for this:

•ZCL_USMD_MATL_VALIDATION — BAdI for material validation with four independent checks: duplicate detection, mandatory field completeness, material-type-specific rules, and plant code verification. I kept these as separate checks rather than one combined rule so errors are specific and actionable for the requestor.
•ZCL_USMD_IDOC_FILTER — BAdI that strips plant-specific segments from IDOCs before distribution. Each plant only receives data relevant to it. This was important to get right — without it, plant data from Plant 1 can land in Plant 3’s system.
•Z_MDG_IDOC_ERROR_MONITOR — Custom error monitoring program with auto-retry logic for transient failures. Built this separately from standard BD87 monitoring to support auto-reprocessing without manual intervention.

Workflow
I configured a single-step approval workflow with a 2-day deadline and automatic escalation to the requestor’s supervisor. Kept it simple intentionally — multi-level approval adds latency and, for most material types in a plant environment, a single materials manager approval is sufficient governance.

Testing
I ran 17 test scenarios end-to-end across all three plant systems. All 17 passed. Key scenarios included:

•New material creation — full IDOC distribution to all 3 plants
•Plant-selective creation — IDOC filtered correctly to relevant plants only
•Duplicate material attempt — rejected by BRF+ before workflow reached
•Workflow escalation — tested with artificial deadline trigger
•IDOC error simulation — forced failure, confirmed auto-retry and alert
•Bulk creation — 100 materials processed to validate performance at volume

Results

Metric
Target
Actual
Material creation time
≤ 6 hours
4.7 minutes average
IDOC success rate
≥ 99%
99.2%
Duplicates post-go-live
Zero
Zero (BRF+ blocking at source)
Data consistency score
≥ 95%
98%
Test scenarios passed
17/17
17/17

The 4.7-minute figure is the average from creation request to activation with IDOC sent. Most of that time is workflow approval — the technical processing itself is under a minute.

What I’d Do Differently
A few things I noted as I went through this:

The BRF+ duplicate check currently matches on material description. In a real implementation I’d push for a more robust approach — description similarity scoring rather than exact match — because slight naming variations will still create near-duplicates that slip through.
The workflow is single-step for all material types. In practice, I’d probably add a second approval step for FERT materials given the valuation class and price control implications, while keeping ROH/HALB as single-step.
I’d also scope in a data remediation workstream for the existing 120+ duplicates. The governance layer prevents new ones but doesn’t address the backlog.

Effort & ROI

Area
Estimated Hours
MDG configuration
~80 hrs
Custom ABAP (3 objects)
~80 hrs
Testing & documentation
~40 hrs
Total
~200 hrs

Projected annual benefit based on duplicate inventory reduction ($180K), manual effort savings (~500 hrs/year at $50/hr), and procurement error reduction ($45K) comes to roughly $250K — approximately 495% ROI on Year 1 effort.

Tech Stack

•SAP ECC 6.0 + MDG 8.0 (hub)
•SAP ECC 6.0 × 3 (receiving plant systems)
•ALE/IDOC — MATMAS message type
•BRF+ for validation rules
•SAP Business Workflow with email integration
•Custom ABAP: BAdI implementations + monitoring program (ZCL_USMD_MATL_VALIDATION, ZCL_USMD_IDOC_FILTER, Z_MDG_IDOC_ERROR_MONITOR)
