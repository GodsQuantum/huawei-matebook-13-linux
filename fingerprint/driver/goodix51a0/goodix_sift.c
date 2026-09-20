/*
 * GXFP51A0 adaptive54 + FAST/BRIEF/RANSAC wrapper
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#include "goodix_sift.h"

#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

static int
gx_cmp_double (const void *a, const void *b)
{
  const double da = *(const double *) a;
  const double db = *(const double *) b;

  return (da > db) - (da < db);
}

static void
gx_secure_clear (void *ptr, gsize len)
{
  volatile guint8 *p = ptr;

  while (ptr && len-- > 0)
    *p++ = 0;
}

static void
gx_unsharp4 (guint8 *img, int w, int h)
{
  g_autofree guint8 *blurred = g_new (guint8, (gsize) w * h);

  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++)
      {
        int sum = 0, weight = 0;

        for (int dy = -1; dy <= 1; dy++)
          {
            int yy = y + dy;
            if (yy < 0 || yy >= h)
              continue;
            for (int dx = -1; dx <= 1; dx++)
              {
                int xx = x + dx;
                int k;
                if (xx < 0 || xx >= w)
                  continue;
                k = (dx == 0 ? 2 : 1) * (dy == 0 ? 2 : 1);
                sum += k * img[yy * w + xx];
                weight += k;
              }
          }
        blurred[y * w + x] = (guint8) (sum / weight);
      }

  for (int i = 0; i < w * h; i++)
    {
      int value = 4 * (int) img[i] - 3 * (int) blurred[i];

      img[i] = (guint8) CLAMP (value, 0, 255);
    }
}

GxSiftFeatures *
gx_sift_extract (const double *img, int w, int h)
{
  const gsize n = (gsize) w * (gsize) h;
  g_autofree double *sorted = NULL;
  g_autofree guint8 *pixels = NULL;
  GxSiftFeatures *features = NULL;
  double lo, hi, scale;

  if (!img || w <= 0 || h <= 0 || n == 0 ||
      n > G_MAXSIZE / sizeof (double))
    return NULL;

  sorted = g_new (double, n);
  pixels = g_new (guint8, n);
  for (gsize i = 0; i < n; i++)
    {
      if (!isfinite (img[i]))
        return NULL;
      sorted[i] = img[i];
    }

  qsort (sorted, n, sizeof *sorted, gx_cmp_double);
  lo = sorted[(n * 1) / 100];
  hi = sorted[(n * 99) / 100];
  if (!(hi > lo + 1.0))
    return NULL;
  scale = 255.0 / (hi - lo);

  for (gsize i = 0; i < n; i++)
    {
      double value = (img[i] - lo) * scale;

      value = CLAMP (value, 0.0, 255.0);
      pixels[i] = (guint8) lround (value);
    }

  gx_unsharp4 (pixels, w, h);
  features = sigfm_extract (pixels, w, h);

  gx_secure_clear (pixels, n);
  gx_secure_clear (sorted, n * sizeof *sorted);
  return features;
}

void
gx_sift_free (GxSiftFeatures *features)
{
  sigfm_free_info (features);
}

guint
gx_sift_keypoints (const GxSiftFeatures *features)
{
  int count = sigfm_keypoints_count ((GxSiftFeatures *) features);

  return count > 0 ? (guint) count : 0;
}

int
gx_sift_match (const GxSiftFeatures *a, const GxSiftFeatures *b)
{
  if (!a || !b)
    return 0;

  return MAX (0, sigfm_match_score ((GxSiftFeatures *) a,
                                    (GxSiftFeatures *) b));
}

GxSiftFeatures *
gx_sift_copy (const GxSiftFeatures *features)
{
  return sigfm_copy_info ((GxSiftFeatures *) features);
}

GByteArray *
gx_sift_serialize (const GxSiftFeatures *features)
{
  int len = 0;
  guint8 *raw;
  GByteArray *result;

  raw = sigfm_serialize_binary ((GxSiftFeatures *) features, &len);
  if (!raw || len <= 0)
    return NULL;

  result = g_byte_array_sized_new ((guint) len);
  g_byte_array_append (result, raw, (guint) len);
  gx_secure_clear (raw, (gsize) len);
  g_free (raw);
  return result;
}



int
gx_sift_pixel_overlap_metrics (const GxSiftFeatures *probe,
                               const GxSiftFeatures *enrolled,
                               int *out_inliers,
                               int *out_overlap,
                               int *out_zncc_milli,
                               int *out_agree_permille)
{
  return sigfm_pixel_overlap_metrics ((SigfmImgInfo *) probe,
                                      (SigfmImgInfo *) enrolled,
                                      out_inliers, out_overlap,
                                      out_zncc_milli,
                                      out_agree_permille);
}

GxSiftFeatures *
gx_sift_deserialize (const guint8 *data, gsize len)
{
  if (!data || len == 0 || len > INT_MAX)
    return NULL;

  return sigfm_deserialize_binary (data, (int) len);
}
