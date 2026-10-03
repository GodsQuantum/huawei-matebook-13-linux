# HANDOFF — GXFP51A0 rel74 image-readout quiet candidate — 2026-10-03

## Why rel74 exists

rel73 made transport deadlines Windows-tolerant but did not yet receive a
human post-READY biometric gate. During review against 2026 hardware-validated
Goodix SPI work, a more fundamental capture hazard was found.

The current GXFP51A0 synchronous GET_IMAGE path could:
1. receive the cleartext GET_IMAGE ACK;
2. wait only 5 ms;
3. clock SPI again while looking for the TLS image.

Recent Chicago/ST411 work proves that after image-setmode ACK the sensor spends
about 73 ms reading the analog array into its buffer. Windows remains silent on
SPI during that window. Repeated SPI reads while IRQ is asserted but the packet
is not ready can truncate/corrupt the image (documented row-cliff failure).

This maps directly to Pegasus symptoms:
- strong FDT/touch detection
- valid TLS images
- matcher scores only 3–4/7
- increased sensitivity after kernel/controller code-generation changes

## rel74 delta over rel73

No matcher, template, enrollment, GPIO, PMK, TLS, OTP or S3 lifecycle change.

Only capture transport:
- after a successful GET_IMAGE ACK, hold SPI completely quiet for 80 ms
- do not continue hunting TLS inside the command drain after that ACK
- the TLS record is consumed afterward by the existing bounded frame reader
- if IRQ is high but a read returns no packet, back off 3 ms before reading again
- same 3 ms empty-read backoff in gx_take_tls_frame() and gx_bio_recv()
- accepted-GET_IMAGE no-replay rule from rel48 remains mandatory

Constants:
- GX_IMAGE_READOUT_SETTLE_US = 80000
- GX_IRQ_HIGH_EMPTY_BACKOFF_US = 3000

## Research basis

berkekbgz/libfprint-goodix-spi:
- gdix51c0_capture_image_raw() suppresses all listener SPI access for 80 ms
  immediately after the image-setmode ACK
- comment records ~73 ms analog row-by-row readout and image corruption from
  SPI traffic during that interval
- async listener also backs off on IRQ-high empty reads

szlukabence/goodix-fingerprint-spi-linux:
- Windows WBDI transcript for GF_ST411SEC_APP_14115 shows image command 0x20
  ACK first, then the 10602-byte TLS image record later

This candidate preserves the known-good rel48/50/59/60/61 lineage and rel73's
1-second Windows-compatible ACK/response deadlines.

## Gates

- new test_image_readout_quiet_source_safety: PASS
- full fingerprint/research make test: PASS
- SOURCE_MANIFEST: PASS
- libfprint build: PASS
- release biometric dump hook: absent
- ACTIVE_SENSOR_IO=NONE during build
- GPIO_WRITES=NONE during build
- MMIO_WRITES=NONE during build
- FIRMWARE_ACTIONS=NONE during build

Package:
- libfprint-goodix51a0 1.94.100.goodix51a0-74
- SHA256:
  255c6b7c12a918ab4cd4e502f3b188599138532febaf7fa903468eee982466fe

Human gate required before any S3 work:
- direct verify or normal lock
- genuine DETECTED_HOLD
- require real image score >=7 and successful authentication
- compare image transport retry count and timing against rel59/60/61
