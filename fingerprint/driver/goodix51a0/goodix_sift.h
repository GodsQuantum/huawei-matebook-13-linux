/*
 * GXFP51A0 FAST/BRIEF/RANSAC compatibility wrapper
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
#pragma once

#include <glib.h>
#include "fastbrief/sigfm.h"

typedef SigfmImgInfo GxSiftFeatures;

GxSiftFeatures *gx_sift_extract (const double *img, int w, int h);
void            gx_sift_free (GxSiftFeatures *features);
guint           gx_sift_keypoints (const GxSiftFeatures *features);
int             gx_sift_match (const GxSiftFeatures *a,
                               const GxSiftFeatures *b);
GByteArray     *gx_sift_serialize (const GxSiftFeatures *features);
GxSiftFeatures *gx_sift_deserialize (const guint8 *data, gsize len);
GxSiftFeatures *gx_sift_copy (const GxSiftFeatures *features);
int             gx_sift_pixel_overlap_metrics (const GxSiftFeatures *probe,
                                                    const GxSiftFeatures *enrolled,
                                                    int *out_inliers,
                                                    int *out_overlap,
                                                    int *out_zncc_milli,
                                                    int *out_agree_permille);
