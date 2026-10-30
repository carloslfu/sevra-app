#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
python3 scripts/generate_brand.py --check
swift build --product sevra-automation-ui-checks -j "${SEVRA_BUILD_JOBS:-4}"
"$(swift build --show-bin-path)/sevra-automation-ui-checks"
swift build --product sevra-extract -j "${SEVRA_BUILD_JOBS:-4}"
swift build --product sevra-extraction-checks -j "${SEVRA_BUILD_JOBS:-4}"
"$(swift build --show-bin-path)/sevra-extraction-checks"
swift build --product sevra-checks -j "${SEVRA_BUILD_JOBS:-4}"
BIN=$(swift build --show-bin-path)
"$BIN/sevra-checks"
swift build --product sevra -j "${SEVRA_BUILD_JOBS:-4}"
python3 scripts/check_schedule_preview.py --cli "$BIN/sevra"
python3 scripts/check_automation_definitions.py --cli "$BIN/sevra"
python3 scripts/check_automation_planning.py --cli "$BIN/sevra" --checks "$BIN/sevra-checks"
swift build --product sevra-automation-durability -j "${SEVRA_BUILD_JOBS:-4}"
python3 scripts/check_automation_durability.py
python3 scripts/check_automation_execution.py --cli "$BIN/sevra" --checks "$BIN/sevra-checks" --worker "$BIN/sevra-automation-durability"
python3 scripts/check_automation_causality.py --cli "$BIN/sevra" --checks "$BIN/sevra-checks"
python3 scripts/check_shared_admissions.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks" --output .build/shared-admissions-check.json
python3 scripts/check_condition_dispatch.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks" --output .build/condition-dispatch-check.json
python3 scripts/check_condition_transitions.py --cli "$BIN/sevra"
python3 scripts/check_business_events.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks"
"$BIN/sevra-checks" --inventory-event-limit
"$BIN/sevra-checks" --inventory-condition-limit
"$BIN/sevra-checks" --condition-input-limit
python3 scripts/check_inventory_event_state.py --cli "$BIN/sevra"
python3 scripts/check_inventory_conditions.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks"
python3 scripts/check_condition_inputs.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks"
python3 scripts/check_automatic_ancestry.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks"
python3 scripts/check_derivation_roles.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks"
python3 scripts/check_business_origins.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks"
python3 scripts/check_condition_origins.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks"
python3 scripts/check_business_inputs.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks"
python3 scripts/check_references.py --cli "$BIN/sevra"
python3 scripts/check_extracted_references.py --cli "$BIN/sevra"
python3 scripts/check_contextual_intake.py --cli "$BIN/sevra"
python3 scripts/check_table_updates.py --cli "$BIN/sevra"
python3 scripts/check_bulk_intake.py --cli "$BIN/sevra"
python3 scripts/check_sheet_formulas.py --cli "$BIN/sevra"
python3 scripts/check_persistence.py --cli "$BIN/sevra"
python3 scripts/check_managed_datasets.py --cli "$BIN/sevra"
python3 scripts/check_dataset_definitions.py --cli "$BIN/sevra"
python3 scripts/check_dataset_queries.py --cli "$BIN/sevra"
python3 scripts/check_application_definitions.py --cli "$BIN/sevra"
python3 scripts/check_computation_views.py --cli "$BIN/sevra"
swift build --product sevra-workflow-durability -j "${SEVRA_BUILD_JOBS:-4}"
python3 scripts/check_workflow_durability.py
python3 scripts/check_workflow_cli.py --cli "$BIN/sevra" --worker "$BIN/sevra-workflow-durability"
python3 scripts/check_application_actions.py --cli "$BIN/sevra"
python3 scripts/check_document_actions.py --cli "$BIN/sevra"
python3 scripts/check_workflow_intake.py --cli "$BIN/sevra"
python3 scripts/check_workflow_lookup.py --cli "$BIN/sevra"
python3 scripts/check_workflow_clarification.py --cli "$BIN/sevra" --worker "$BIN/sevra-workflow-durability"
python3 scripts/check_space_editing.py "$BIN/sevra"
swift build --product sevra-benchmark -j "${SEVRA_BUILD_JOBS:-4}"
"$BIN/sevra-benchmark" --self-check
swift build --product sevra-document-checks -j "${SEVRA_BUILD_JOBS:-4}"
"$BIN/sevra-document-checks"
swift build --product sevra-preview-checks -j "${SEVRA_BUILD_JOBS:-4}"
"$BIN/sevra-preview-checks"
python3 scripts/check_large_preview.py --binary "$BIN/sevra-preview-checks"
swift build --product sevra-context-durability -j "${SEVRA_BUILD_JOBS:-4}"
python3 scripts/check_context_durability.py
swift build --product sevra-table-ui-checks -j "${SEVRA_BUILD_JOBS:-4}"
"$BIN/sevra-table-ui-checks"
swift build --product sevra-search-ui-checks -j "${SEVRA_BUILD_JOBS:-4}"
"$BIN/sevra-search-ui-checks"
swift build --product sevra-voice-checks -j "${SEVRA_BUILD_JOBS:-4}"
"$BIN/sevra-voice-checks"
swift build --product sevra-product-checks -j "${SEVRA_BUILD_JOBS:-4}"
"$BIN/sevra-product-checks"
swift build --product sevra-splash-checks -j "${SEVRA_BUILD_JOBS:-4}"
"$BIN/sevra-splash-checks"
swift build --product sevra-native-setup -j "${SEVRA_BUILD_JOBS:-4}"
"$BIN/sevra-native-setup" --help
if "$BIN/sevra-native-setup" --unknown-option; then
  echo 'Native setup accepted an unknown option as a download path.' >&2
  exit 1
fi
swift build --product sevra-splash-text-checks -j "${SEVRA_BUILD_JOBS:-4}"
python3 scripts/check_splash_text.py
python3 scripts/build_guidance.py
swift build --product sevra-splash-grammar-checks -j "${SEVRA_BUILD_JOBS:-4}"
swift build --product sevra-agent-checks -j "${SEVRA_BUILD_JOBS:-4}"
python3 scripts/check_splash_grammar.py
python3 scripts/check_performance_harness.py
swift build --product sevra-workflow-performance -j "${SEVRA_BUILD_JOBS:-4}"
"$BIN/sevra-workflow-performance" --self-check
python3 scripts/check_workflow_diagnostics.py
python3 scripts/check_workflow_prefix.py
python3 scripts/check_workflow_isolation.py
python3 scripts/check_request_cache_isolation.py
python3 scripts/check_item_reference_probe.py
python3 scripts/check_links.py
if command -v dbmd >/dev/null; then dbmd validate --all db --json; else echo 'dbmd is required for specification validation.' >&2; exit 1; fi
