#!/usr/bin/env python3
import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

SEQUENCE = [
    ("INDEX DROIT", "genuine", 1, 3),
    ("INDEX DROIT", "genuine", 2, 3),
    ("INDEX DROIT", "genuine", 3, 3),
    ("INDEX GAUCHE", "impostor", 1, 1),
    ("MAJEUR GAUCHE", "impostor", 1, 1),
    ("MAJEUR DROIT", "impostor", 1, 1),
]

def countdown(seconds):
    for n in range(seconds, 0, -1):
        print(f"  {n}...", flush=True)
        time.sleep(1)

def main():
    ap = argparse.ArgumentParser(
        description="Compare several physical fingers against one enrolled template")
    ap.add_argument("-f", "--finger", default="right-index-finger")
    ap.add_argument("-u", "--user", default=os.environ.get("USER", ""))
    ap.add_argument("--timeout", type=int, default=60)
    args = ap.parse_args()

    if not args.user:
        raise SystemExit("ERROR: user name is empty")

    here = Path(__file__).resolve().parent
    verifier = here / "gxfp51a0-verify-diagnostic.py"
    if not verifier.exists():
        raise SystemExit(f"ERROR: verifier not found: {verifier}")

    state_root = Path(os.environ.get(
        "XDG_STATE_HOME", str(Path.home() / ".local/state")))
    out_dir = state_root / "gxfp51a0"
    out_dir.mkdir(parents=True, exist_ok=True)
    run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
    aggregate_path = out_dir / f"compare-{run_id}.json"
    results = []

    print("=" * 76)
    print(" GXFP51A0 — COMPARAISON MULTI-DOIGTS")
    print("=" * 76)
    print("Template enregistré comparé : RIGHT INDEX / right-index-finger")
    print("6 scans : 3 genuine + 3 contrôles négatifs.")
    print("Suis uniquement les ordres affichés dans ce terminal.")
    print()

    for idx, (label, group, rep, total) in enumerate(SEQUENCE, start=1):
        print()
        print("!" * 76)
        print(f"!!! TEST {idx}/6 — {label} !!")
        if total > 1:
            print(f"!!! PASSAGE {rep}/{total} — {label} !!")
        print("!" * 76)

        summary_path = out_dir / f"compare-{run_id}-{idx:02d}.json"
        cmd = [
            sys.executable, str(verifier),
            "--finger", args.finger,
            "--user", args.user,
            "--physical-label", label,
            "--summary-json", str(summary_path),
            "--timeout", str(args.timeout),
        ]

        proc = subprocess.run(cmd, check=False)
        if summary_path.exists():
            data = json.loads(summary_path.read_text(encoding="utf-8"))
        else:
            data = {
                "physical_label": label,
                "template_finger": args.finger,
                "verdict": "NO_SUMMARY",
                "score": None,
                "threshold": None,
                "capture_ms": None,
                "log_path": None,
            }
        data["group"] = group
        data["repetition"] = rep
        data["process_exit"] = proc.returncode
        results.append(data)

        if idx != len(SEQUENCE):
            print()
            print(">>> RETIRE TOUT DOIGT DU CAPTEUR <<<")
            print("Prochain test dans :")
            countdown(4)

    aggregate_path.write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print()
    print("=" * 76)
    print(" RÉSULTATS COMPARATIFS")
    print("=" * 76)
    print(f"{'DOIGT':<18} {'TYPE':<9} {'SCORE':<10} {'VERDICT'}")
    print("-" * 76)
    for item in results:
        score = item.get("score")
        threshold = item.get("threshold")
        score_txt = (
            f"{score}/{threshold}"
            if score is not None and threshold is not None
            else "n/a"
        )
        print(
            f"{item['physical_label']:<18} "
            f"{item['group']:<9} "
            f"{score_txt:<10} "
            f"{item['verdict']}"
        )

    genuine = [
        x["score"] for x in results
        if x["group"] == "genuine" and isinstance(x.get("score"), int)
    ]
    impostor = [
        x["score"] for x in results
        if x["group"] == "impostor" and isinstance(x.get("score"), int)
    ]

    if genuine:
        print(
            "GENUINE : "
            f"min={min(genuine)} max={max(genuine)} "
            f"moyenne={statistics.mean(genuine):.2f}"
        )
    if impostor:
        print(
            "IMPOSTOR: "
            f"min={min(impostor)} max={max(impostor)} "
            f"moyenne={statistics.mean(impostor):.2f}"
        )
    print(f"Rapport JSON : {aggregate_path}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
