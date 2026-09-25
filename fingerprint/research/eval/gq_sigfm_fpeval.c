/* SPDX-License-Identifier: LGPL-2.1-or-later
 * Thin fp_eval ABI adapter for the exact GXFP51A0 matcher shipped here.
 * Compatible with Sigfrodr/libfprint-goodixtls tools/eval --backend-so ABI v1.
 */
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include "../../driver/goodix51a0/goodix_sift.h"

static void secure_clear(void *ptr, size_t len)
{
  volatile uint8_t *p = (volatile uint8_t *) ptr;
  while (ptr && len--)
    *p++ = 0;
}

const char *fpeval_name(void)
{
  return "gq-sigfm";
}

void *fpeval_extract(const uint8_t *img, int width, int height)
{
  size_t n;
  double *gray;
  GxSiftFeatures *feat;

  if (!img || width <= 0 || height <= 0)
    return NULL;
  if ((size_t) width > SIZE_MAX / (size_t) height)
    return NULL;

  n = (size_t) width * (size_t) height;
  if (n > SIZE_MAX / sizeof(*gray))
    return NULL;

  gray = malloc(n * sizeof(*gray));
  if (!gray)
    return NULL;

  for (size_t i = 0; i < n; i++)
    gray[i] = (double) img[i];

  feat = gx_sift_extract(gray, width, height);
  secure_clear(gray, n * sizeof(*gray));
  free(gray);
  return feat;
}

double fpeval_score(void *probe, void *gallery)
{
  if (!probe || !gallery)
    return 0.0;
  return (double) gx_sift_match((const GxSiftFeatures *) probe,
                                (const GxSiftFeatures *) gallery);
}

void fpeval_free(void *feat)
{
  gx_sift_free((GxSiftFeatures *) feat);
}
