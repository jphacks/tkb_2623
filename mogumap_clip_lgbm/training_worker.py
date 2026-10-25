"""Cloud Run Job entrypoint. Durable claims and fencing live in Postgres."""
from __future__ import annotations

import argparse
import json
import logging
import threading
import time

from history import snapshot
from policy import training_due
from repository import Repository

log = logging.getLogger(__name__)


class LostLease(RuntimeError):
    pass


class Heartbeat:
    def __init__(self, repository: Repository, job_id: str):
        self.repository, self.job_id = repository, job_id
        self.stop = threading.Event()
        self.lost = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        while not self.stop.wait(30):
            try:
                if not self.repository.rpc("ai_heartbeat_training", p_job_id=self.job_id):
                    self.lost.set()
                    return
            except Exception:
                # Publication also checks the lease; conservatively do not publish.
                self.lost.set()
                return

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.stop.set()
        self.thread.join(timeout=50)

    def check(self):
        if self.lost.is_set():
            raise LostLease("training lease unavailable")


def process_job(repository: Repository, job: dict, *, force: bool = False) -> dict:
    job_id, user_id = job["id"], job["user_id"]
    try:
        with Heartbeat(repository, job_id) as heartbeat:
            records = repository.history(user_id)
            status = repository.status(user_id)
            if not training_due(records, status, force or job["repair_requested"]):
                if not repository.rpc("ai_finish_training", p_job_id=job_id, p_outcome="skipped"):
                    raise LostLease("cannot complete skipped job")
                return {"job_id": job_id, "outcome": "skipped", "valid_records": len(records)}
            heartbeat.check()
            if not repository.rpc("ai_heartbeat_training", p_job_id=job_id, p_snapshot=snapshot(records)):
                raise LostLease("cannot store training snapshot")
            from ml import train_user
            stats = train_user(user_id, records, version=job_id)
            heartbeat.check()
            if not repository.rpc("ai_finish_training", p_job_id=job_id, p_outcome="succeeded", p_stats=stats):
                raise LostLease("cannot publish model")
            return {"job_id": job_id, "outcome": "succeeded", **stats}
    except Exception as exc:
        # Exception bodies may contain signed URLs or auth data; keep only class.
        code = type(exc).__name__
        try:
            repository.rpc("ai_finish_training", p_job_id=job_id, p_outcome="failed", p_error_code=code)
        except Exception:
            log.error("job_completion_failed job_id=%s error=%s", job_id, code)
        log.error("training_failed job_id=%s error=%s", job_id, code)
        return {"job_id": job_id, "outcome": "failed", "error_code": code}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-users", type=int, default=10)
    parser.add_argument("--max-seconds", type=int, default=600)
    parser.add_argument("--seed-user", help="Mark an existing user dirty, e.g. to retry an exhausted job")
    args = parser.parse_args()
    if args.max_users < 1 or args.max_seconds < 1:
        parser.error("limits must be positive")
    repository = Repository()
    if args.seed_user:
        repository.rpc("ai_mark_dirty", p_user_id=args.seed_user)
        return 0
    started, failed = time.monotonic(), False
    for _ in range(args.max_users):
        if time.monotonic() - started >= args.max_seconds:
            break
        jobs = repository.rpc("ai_claim_training")
        if not jobs:
            break
        result = process_job(repository, jobs[0])
        print(json.dumps(result, ensure_ascii=False), flush=True)
        failed |= result["outcome"] == "failed"
    return 1 if failed else 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    raise SystemExit(main())
