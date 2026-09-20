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

SERVICE = "net.reactivated.Fprint"
MANAGER = "/net/reactivated/Fprint/Manager"
MANAGER_IFACE = "net.reactivated.Fprint.Manager"
DEVICE_IFACE = "net.reactivated.Fprint.Device"

SCORE_RE = re.compile(r"verify: attempt \d+(?:/\d+)? -> (\d+) matches \(best=\d+ threshold=(\d+)")
RETRY_RE = re.compile(r"verify: no-match attempt (\d+)/(\d+); request another complete press")
CAPTURE_MS_RE = re.compile(r"timing: whole capture (\d+) us")
RESULT_RE = re.compile(r"Verify result: (verify-[a-z-]+) \((not )?done\)")

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

def get_device_path():
    out = subprocess.check_output(
        ["busctl", "--system", "call", SERVICE, MANAGER,
         MANAGER_IFACE, "GetDefaultDevice"],
        text=True, stderr=subprocess.STDOUT, timeout=15,
    ).strip()
    m = re.fullmatch(r'o "([^"]+)"', out)
    if not m:
        raise RuntimeError(f"unexpected GetDefaultDevice output: {out}")
    return m.group(1)

def get_finger_state(device):
    out = subprocess.check_output(
        ["busctl", "--system", "get-property", SERVICE, device,
         DEVICE_IFACE, "finger-needed", "finger-present"],
        text=True, stderr=subprocess.STDOUT, timeout=3,
    ).splitlines()
    if len(out) != 2:
        raise RuntimeError(f"unexpected property output: {out}")
    parse = lambda s: s.strip().endswith("true")
    return parse(out[0]), parse(out[1])

def main():
    ap = argparse.ArgumentParser(
        description="Guided GXFP51A0/fprintd verify diagnostic")
    ap.add_argument("-f", "--finger", default="right-index-finger")
    ap.add_argument("-u", "--user", default=os.environ.get("USER", ""))
    ap.add_argument("--physical-label", default="INDEX DROIT")
    ap.add_argument("--summary-json")
    ap.add_argument("--timeout", type=int, default=60)
    args = ap.parse_args()

    for cmd in ("busctl", "fprintd-verify", "journalctl", "stdbuf"):
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

    device = get_device_path()
    print(f"fprintd device : {device}")
    print("Initialisation du test…")

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
    present_prev = False
    remove_announced = False
    score = threshold = capture_ms = None
    final_result = None
    final_result_at = None
    start = time.monotonic()

    with log_path.open("w", encoding="utf-8") as log:
        try:
            while time.monotonic() - start < args.timeout:
                try:
                    needed, present = get_finger_state(device)
                except Exception as exc:
                    log.write(f"[state-error] {exc}\n")
                    needed = present = False

                if needed and not ready_announced and not present:
                    ready_announced = True
                    print("CAPTEUR PRÊT. POSE dans :")
                    countdown()
                    beep()
                    print(f">>> POSE : {physical_label} !! — ET GARDE-LE <<<", flush=True)

                if present and not present_prev:
                    beep()
                    print(f">>> {physical_label} DÉTECTÉ — GARDE-LE <<<", flush=True)

                if present_prev and not present and not remove_announced:
                    print("!!! DOIGT RETIRÉ AVANT LE VERDICT — ATTENDS LE PROCHAIN « POSE »",
                          flush=True)
                    ready_announced = False

                present_prev = present

                for key, _ in sel.select(timeout=0.20):
                    line = key.fileobj.readline()
                    if not line:
                        continue
                    line = line.rstrip()
                    log.write(f"[{key.data}] {line}\n")
                    log.flush()

                    if key.data == "journal":
                        m = SCORE_RE.search(line)
                        if m:
                            score, threshold = map(int, m.groups())
                        m = CAPTURE_MS_RE.search(line)
                        if m:
                            capture_ms = int(m.group(1)) / 1000.0
                        m = RETRY_RE.search(line)
                        if m:
                            attempt, total = map(int, m.groups())
                            ready_announced = False
                            print(
                                f"SCAN {attempt}/{total} NON RETENU. "
                                "RETIRE LE DOIGT, puis attends le prochain « POSE ».",
                                flush=True,
                            )
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
