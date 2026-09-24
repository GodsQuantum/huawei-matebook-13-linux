#!/usr/bin/env python3
import argparse
import json
import os
import re
import selectors
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path

SCORE_RE = re.compile(r"verify: attempt \d+(?:/\d+)? -> (\d+) matches \(best=\d+ threshold=(\d+)")
RETRY_RE = re.compile(r"verify: no-match attempt (\d+)/(\d+); request another complete press")
CAPTURE_MS_RE = re.compile(r"timing: whole capture (\d+) us")
RESULT_RE = re.compile(r"Verify result: (verify-[a-z-]+) \((not )?done\)")
TRACE_READY_RE = re.compile(r"GXFP51A0 (?:VERIFY|IDENTIFY)_TRACE physical press (\d+)/(\d+) READY")
TRACE_DETECTED_RE = re.compile(r"GXFP51A0 (?:VERIFY|IDENTIFY)_TRACE physical press (\d+)/(\d+) DETECTED_HOLD")
TRACE_LIFT_RE = re.compile(r"GXFP51A0 (?:VERIFY|IDENTIFY)_TRACE physical press (\d+)/(\d+) LIFT_NOW")
TRACE_RELEASED_RE = re.compile(r"GXFP51A0 (?:VERIFY|IDENTIFY)_TRACE physical press (\d+)/(\d+) RELEASED")
TRACE_SCORE_RE = re.compile(r"GXFP51A0 AUTH_TRACE mode=(?:verify|identify) same-press image (\d+)/(\d+) score=(\d+) threshold=(\d+)")
TRACE_DONE_RE = re.compile(r"GXFP51A0 AUTH_TRACE mode=(?:verify|identify) same-press completed images=(\d+) best=(\d+) threshold=(\d+)")

def beep():
    print("\a", end="", flush=True)

def countdown():
    for n in (3, 2, 1):
        print(f"  {n}...", flush=True)
        time.sleep(1)

def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)

def main():
    ap = argparse.ArgumentParser(
        description="Guided GXFP51A0/fprintd verify diagnostic")
    ap.add_argument("-f", "--finger", default="right-index-finger")
    ap.add_argument("-u", "--user", default=os.environ.get("USER", ""))
    ap.add_argument("--physical-label", default="INDEX DROIT")
    ap.add_argument("--summary-json")
    ap.add_argument("--timeout", type=int, default=60)
    args = ap.parse_args()

    for cmd in ("fprintd-verify", "journalctl", "stdbuf"):
        if not shutil.which(cmd):
            raise SystemExit(f"ERROR: missing required command: {cmd}")
    if not args.user:
        raise SystemExit("ERROR: user name is empty")

    state_root = Path(os.environ.get(
        "XDG_STATE_HOME", str(Path.home() / ".local/state")))
    log_dir = state_root / "gxfp51a0"
    log_dir.mkdir(parents=True, exist_ok=True)
    run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
    log_path = log_dir / f"verify-{run_id}.log"

    physical_label = args.physical_label.upper()
    print("!" * 72)
    print(f"!!! DOIGT À UTILISER : {physical_label} !!")
    print("!" * 72)
    print(" GXFP51A0 — VERIFY GUIDÉ")
    print(f"Template comparé : {args.finger}")
    print("RÈGLE : ne touche pas le capteur avant « POSE ».")
    print("RÈGLE : garde le doigt jusqu'à « RETIRE ».")
    print()

    print("Initialisation du test…")
    print("Aucune pose ne sera demandée avant le marqueur READY du driver.")

    journal = subprocess.Popen(
        ["journalctl", "-u", "fprintd.service", "-f", "-n", "0",
         "-o", "cat", "--no-pager"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    verify = subprocess.Popen(
        ["stdbuf", "-oL", "-eL", "fprintd-verify",
         "-f", args.finger, args.user],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )

    sel = selectors.DefaultSelector()
    sel.register(verify.stdout, selectors.EVENT_READ, "client")
    sel.register(journal.stdout, selectors.EVENT_READ, "journal")

    ready_announced = False
    remove_announced = False
    score = threshold = capture_ms = None
    final_result = None
    final_result_at = None
    start = time.monotonic()

    with log_path.open("w", encoding="utf-8") as log:
        try:
            while time.monotonic() - start < args.timeout:
                for key, _ in sel.select(timeout=0.20):
                    line = key.fileobj.readline()
                    if not line:
                        continue
                    line = line.rstrip()
                    log.write(f"[{key.data}] {line}\n")
                    log.flush()

                    if key.data == "journal":
                        m = TRACE_READY_RE.search(line)
                        if m:
                            attempt, total = map(int, m.groups())
                            ready_announced = True
                            beep()
                            print(f">>> POSE : {physical_label} — tentative physique {attempt}/{total} <<<",
                                  flush=True)
                            continue
                        m = TRACE_DETECTED_RE.search(line)
                        if m:
                            attempt, total = map(int, m.groups())
                            print(f">>> DÉTECTÉ {attempt}/{total} — GARDE LE DOIGT POSÉ <<<",
                                  flush=True)
                            continue
                        m = TRACE_SCORE_RE.search(line)
                        if m:
                            image, total_images, score, threshold = map(int, m.groups())
                            print(f"[rel38] image same-press {image}/{total_images} : "
                                  f"score {score} / seuil {threshold}", flush=True)
                            continue
                        m = TRACE_DONE_RE.search(line)
                        if m:
                            images, best, threshold = map(int, m.groups())
                            score = best
                            print(f"[rel38] pose analysée : {images} image(s), "
                                  f"meilleur score {best} / seuil {threshold}", flush=True)
                            continue
                        m = TRACE_LIFT_RE.search(line)
                        if m:
                            beep()
                            print(f">>> RETIRE {physical_label} MAINTENANT <<<", flush=True)
                            remove_announced = True
                            continue
                        m = TRACE_RELEASED_RE.search(line)
                        if m:
                            print(">>> RETRAIT CONFIRMÉ PAR LE DRIVER <<<", flush=True)
                            ready_announced = False
                            continue
                        m = SCORE_RE.search(line)
                        if m:
                            score, threshold = map(int, m.groups())
                        m = CAPTURE_MS_RE.search(line)
                        if m:
                            capture_ms = int(m.group(1)) / 1000.0
                        continue

                    if line.startswith("Verifying:"):
                        print(f"[fprintd] Template comparé : {args.finger}", flush=True)
                    else:
                        print(f"[fprintd] {line}", flush=True)
                    m = RESULT_RE.search(line)
                    if not m:
                        continue

                    result, not_done = m.groups()
                    if not_done:
                        if result == "verify-retry-scan":
                            ready_announced = False
                            print("SCAN À REFAIRE. Ne touche plus le capteur ; "
                                  "attends le prochain « POSE ».", flush=True)
                        continue

                    final_result = result
                    final_result_at = time.monotonic()

                    if not remove_announced:
                        remove_announced = True
                        beep()
                        print(f">>> RETIRE {physical_label} MAINTENANT <<<", flush=True)

                if final_result:
                    score_ready = score is not None and threshold is not None
                    journal_grace_elapsed = (
                        final_result_at is not None and
                        time.monotonic() - final_result_at >= 1.5
                    )
                    if score_ready or journal_grace_elapsed:
                        break
                if verify.poll() is not None and not final_result:
                    if not ready_announced:
                        print("ÉCHEC INIT/CLAIM : le driver n’a jamais émis READY ; "
                              "aucune pose de doigt n’était attendue.", flush=True)
                    break

            if not final_result:
                print("TIMEOUT/ABORT : aucun verdict terminal obtenu.", flush=True)
        finally:
            stop_process(verify)
            stop_process(journal)

    print()
    print("=" * 64)
    print(" RÉSULTAT")
    print("=" * 64)
    print(f"Doigt   : {physical_label}")
    print(f"Verdict : {final_result or 'UNKNOWN'}")
    if score is not None and threshold is not None:
        print(f"Score   : {score} / seuil {threshold}")
    if capture_ms is not None:
        print(f"Capture : {capture_ms:.1f} ms")
    print(f"Log     : {log_path}")

    if args.summary_json:
        summary = {
            "physical_label": physical_label,
            "template_finger": args.finger,
            "verdict": final_result or "UNKNOWN",
            "score": score,
            "threshold": threshold,
            "capture_ms": capture_ms,
            "log_path": str(log_path),
        }
        Path(args.summary_json).write_text(
            json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    if final_result == "verify-match":
        return 0
    if final_result == "verify-no-match":
        return 1
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
