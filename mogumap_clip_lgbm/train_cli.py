"""Developer-only manual training. Defaults to isolated output, never publication."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from history import valid_history
from policy import MIN_TRAIN_RECORDS, training_due


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--records", type=Path, help="JSON dataset (no Supabase writes)")
    source.add_argument("--source", choices=["supabase"])
    parser.add_argument("--user-id", default=os.getenv("TRAIN_USER_ID"))
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent / "artifacts/manual")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true", help="Bypass the 5-new-record gate, never the 6-record minimum")
    parser.add_argument("--gcs-test", action="store_true", help="Save test artifacts under GCS manual-tests/, never publish")
    parser.add_argument("--publish", action="store_true", help="Explicitly publish through the DB lease protocol (Supabase only)")
    args = parser.parse_args()
    if not args.user_id:
        parser.error("--user-id or TRAIN_USER_ID is required")
    if args.gcs_test and (args.records or args.publish or not os.getenv("MODEL_BUCKET")):
        parser.error("--gcs-test requires --source supabase and MODEL_BUCKET; cannot combine with --publish")
    if args.publish and (args.records or args.dry_run):
        parser.error("--publish requires --source supabase, without --dry-run")
    repository, status = None, None
    if args.records:
        raw = json.loads(args.records.read_text())
        records = valid_history([r for r in raw if str(r.get("user_id")) == args.user_id], args.user_id)
    else:
        from repository import Repository
        repository = Repository()
        records, status = repository.history(args.user_id), repository.status(args.user_id)
    eligible = training_due(records, status, args.force)
    if args.dry_run:
        print(json.dumps({"valid_records": len(records), "training_due": eligible, "publish": False}))
        return 0
    if len(records) < MIN_TRAIN_RECORDS:
        parser.error(f"at least {MIN_TRAIN_RECORDS} valid records are required (has {len(records)})")
    if not eligible:
        print(json.dumps({"outcome": "skipped", "reason": "fewer_than_5_new_records", "publish": False}))
        return 0
    if args.publish:
        # Ensure a dirty row exists, then re-read and revalidate inside process_job.
        repository.rpc("ai_mark_dirty", p_user_id=args.user_id)
        jobs = repository.rpc("ai_claim_training", p_user_id=args.user_id, p_force=args.force)
        if not jobs:
            parser.error("training is already running or waiting for retry")
        from training_worker import process_job
        result = process_job(repository, jobs[0], force=args.force)
    else:
        from ml import train_user
        result = {"publish": False, **train_user(
            args.user_id, records, output_dir=None if args.gcs_test else args.output_dir,
            storage_prefix="manual-tests" if args.gcs_test else "models",
        )}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if result.get("outcome") == "failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
