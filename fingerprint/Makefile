.PHONY: verify verify-no-build build research passive-audit help

help:
	@printf '%s\n' \
	  'GXFP51A0 targets:' \
	  '  make verify          software tests + reproducible libfprint build' \
	  '  make verify-no-build software tests only; no network build' \
	  '  make build           build candidate against libfprint v1.94.100' \
	  '  make research        run the research unit/safety suite' \
	  '  make passive-audit   read-only Linux platform inventory'

verify:
	./scripts/verify-software-baseline.sh

verify-no-build:
	./scripts/verify-software-baseline.sh --no-build

build:
	./scripts/build-libfprint-v1.94.100.sh

research:
	$(MAKE) -C research test

passive-audit:
	./scripts/passive-linux-observability.sh
