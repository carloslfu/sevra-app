#!/bin/bash
# The app's checks, one list for this Mac and hosted CI.
#   scripts/check.sh --quick   every push: sources, one build of every product and the fast checks
#   scripts/check.sh           once on a release candidate: the quick checks, then the slow
#                              scale, crash-recovery and command-line journeys and the packaged app
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
case "${1:-}" in
  --quick) QUICK=1 ;;
  '') QUICK=0 ;;
  *) echo 'Usage: scripts/check.sh [--quick]' >&2; exit 2 ;;
esac
JOBS=${SEVRA_BUILD_JOBS:-4}
if ! command -v dbmd >/dev/null; then
  echo 'dbmd is required for specification validation.' >&2
  exit 1
fi

# Quick checks.
dbmd validate --all db --json
python3 scripts/check_links.py
python3 scripts/generate_brand.py --check
python3 scripts/prompt_header.py self-test
python3 scripts/chat_timing.py --self-test
npm ci --prefix sdk --ignore-scripts
python3 scripts/check_native_app_sources.py
python3 scripts/check_excel_business_qualification.py
npm test --prefix sdk
npm run typecheck --prefix sdk
python3 scripts/build_guidance.py
swift build -j "$JOBS"
BIN=$(swift build --show-bin-path)
python3 scripts/check_native_apps.py
# The core checks in three shares at once, one per core on hosted CI.
CORE=()
for share in 0 1 2; do
  "$BIN/sevra-checks" --share "$share/3" > ".build/core-checks-$share.log" 2>&1 &
  CORE+=($!)
done
CORE_FAILED=0
for process in "${CORE[@]}"; do wait "$process" || CORE_FAILED=1; done
cat .build/core-checks-0.log .build/core-checks-1.log .build/core-checks-2.log
if [ "$CORE_FAILED" = 1 ]; then
  echo 'The core checks failed.' >&2
  exit 1
fi
"$BIN/sevra-extraction-checks"
"$BIN/sevra-automation-ui-checks"
"$BIN/sevra-voice-checks"
"$BIN/sevra-document-checks"
"$BIN/sevra-preview-checks"
"$BIN/sevra-preview-checks" --visual-media
"$BIN/sevra-table-ui-checks"
"$BIN/sevra-search-ui-checks"
"$BIN/sevra-product-checks"
"$BIN/sevra-splash-checks"
"$BIN/sevra-native-setup" --help
if "$BIN/sevra-native-setup" --unknown-option; then
  echo 'Native setup accepted an unknown option as a download path.' >&2
  exit 1
fi
python3 scripts/check_splash_text.py
python3 scripts/check_performance_harness.py
"$BIN/sevra-workflow-performance" --self-check
python3 scripts/check_workflow_diagnostics.py
python3 scripts/check_workflow_prefix.py
python3 scripts/check_workflow_isolation.py
python3 scripts/check_request_cache_isolation.py
python3 scripts/check_item_reference_probe.py
# The grammar checks, then the whole default agent suite.
python3 scripts/check_splash_grammar.py
"$BIN/sevra-agent-checks" --sql-tool
SEVRA_CLI="$BIN/sevra" python3 scripts/check_chat_sql.py
SEVRA_CLI="$BIN/sevra" python3 scripts/check_chat_run.py
if [ "$QUICK" = 1 ]; then
  echo 'PASS quick checks'
  exit 0
fi

# Scale limits, crash recovery and the search benchmark.
"$BIN/sevra-checks" --inventory-event-limit
"$BIN/sevra-checks" --inventory-condition-limit
"$BIN/sevra-checks" --condition-input-limit
"$BIN/sevra-benchmark" --self-check
python3 scripts/check_large_preview.py --binary "$BIN/sevra-preview-checks"
python3 scripts/check_context_durability.py
python3 scripts/check_automation_durability.py
python3 scripts/check_workflow_durability.py
python3 scripts/check_workflow_cli.py --cli "$BIN/sevra" --worker "$BIN/sevra-workflow-durability"
python3 scripts/check_native_app_authoring.py

# Command-line journeys.
python3 scripts/check_schedule_preview.py --cli "$BIN/sevra"
python3 scripts/check_automation_definitions.py --cli "$BIN/sevra"
python3 scripts/check_automation_planning.py --cli "$BIN/sevra" --checks "$BIN/sevra-checks"
python3 scripts/check_automation_execution.py --cli "$BIN/sevra" --checks "$BIN/sevra-checks" --worker "$BIN/sevra-automation-durability"
python3 scripts/check_automation_causality.py --cli "$BIN/sevra" --checks "$BIN/sevra-checks"
python3 scripts/check_shared_admissions.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks" --output .build/shared-admissions-check.json
python3 scripts/check_condition_dispatch.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks" --output .build/condition-dispatch-check.json
python3 scripts/check_condition_transitions.py --cli "$BIN/sevra"
python3 scripts/check_business_events.py --cli "$BIN/sevra" --worker "$BIN/sevra-checks"
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
python3 scripts/check_application_actions.py --cli "$BIN/sevra"
python3 scripts/check_document_actions.py --cli "$BIN/sevra"
python3 scripts/check_workflow_intake.py --cli "$BIN/sevra"
python3 scripts/check_workflow_lookup.py --cli "$BIN/sevra"
python3 scripts/check_workflow_clarification.py --cli "$BIN/sevra" --worker "$BIN/sevra-workflow-durability"
python3 scripts/check_space_editing.py "$BIN/sevra"
python3 scripts/check_concurrency.py --cli "$BIN/sevra"
python3 scripts/check_document_cli.py --cli "$BIN/sevra"
python3 scripts/check_history.py --cli "$BIN/sevra" --checks "$BIN/sevra-checks"
python3 scripts/check_receipts.py --cli "$BIN/sevra" --checks "$BIN/sevra-checks"
python3 scripts/check_urls.py --cli "$BIN/sevra"
# Transcription needs the Mac's speech model, which hosted CI does not have.
if [ -z "${CI:-}" ]; then python3 scripts/check_transcription.py --cli "$BIN/sevra"; fi

# The packaged app. Its journeys test the last package build, so only one at least as new
# as the sources counts. Hosted CI has no model, so it checks the package's paths only.
current() { [ -x "$1" ] && [ -z "$(find Sources Package.swift -newer "$1" -print -quit)" ]; }
if current output/native/bin/sevra; then
  python3 scripts/check_native_package.py ${CI:+--paths-only}
  python3 scripts/check_install.py
  python3 scripts/check_extraction_package.py
  swift build --scratch-path .build/native-product -c release --product sevra-extraction-checks -j "$JOBS"
  .build/native-product/release/sevra-extraction-checks
elif [ -n "${CI:-}" ]; then
  echo 'The packaged app is missing or older than the sources: run scripts/build_native.sh first.' >&2
  exit 1
else
  echo 'Skipped the packaged app journeys: run scripts/build_native.sh first.' >&2
fi
echo 'PASS all checks'
