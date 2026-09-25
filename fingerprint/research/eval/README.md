# gq-sigfm fp_eval plug-in

This directory contains a thin ABI adapter for the actual matcher shipped by this driver:
`goodix_sift.c` + `fastbrief/sigfm.c`.

It implements the `--backend-so` ABI introduced by
`Sigfrodr/libfprint-goodixtls tools/eval/fp_eval.py`:

- `fpeval_extract`
- `fpeval_score`
- `fpeval_free`
- `fpeval_name`

Build:

    ./build-gq-sigfm-fpeval.sh

Then use Sigfrodr's evaluator with a local private capture set:

    python3 fp_eval.py --captures ./captures --sensor "GXFP51A0 80x64" --backend-so ./gq_sigfm.so

Use the same `--sensor`, `--enroll`, and `--repeats` as the corresponding reference-backend run.
The adapter performs no capture/template I/O and contains no networking.
Do not commit captures, templates, or per-capture results; share aggregate EER/FAR/FRR only.
