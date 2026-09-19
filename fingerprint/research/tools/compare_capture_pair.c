#define _GNU_SOURCE
#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../driver/goodix51a0/goodix_sift.h"

#define W 80
#define H 64
#define N (W * H)

static int cmp_double(const void *a, const void *b)
{
    const double x = *(const double *)a;
    const double y = *(const double *)b;
    return (x > y) - (x < y);
}

static int read_u16le(const char *path, uint16_t out[N])
{
    FILE *f = fopen(path, "rb");
    unsigned char buf[N * 2];
    size_t n;
    int i;
    if (!f) {
        fprintf(stderr, "open %s: %s\n", path, strerror(errno));
        return -1;
    }
    n = fread(buf, 1, sizeof buf, f);
    fclose(f);
    if (n != sizeof buf) {
        fprintf(stderr, "invalid capture size %s: %zu\n", path, n);
        return -1;
    }
    for (i = 0; i < N; i++)
        out[i] = (uint16_t)buf[2*i] | ((uint16_t)buf[2*i+1] << 8);
    return 0;
}

static double percentile(const double *a, int n, double q)
{
    double *tmp = malloc(sizeof(*tmp) * (size_t)n);
    double pos, frac, v;
    int lo, hi;
    if (!tmp) return 0.0;
    memcpy(tmp, a, sizeof(*tmp) * (size_t)n);
    qsort(tmp, (size_t)n, sizeof(*tmp), cmp_double);
    pos = q * (double)(n - 1);
    lo = (int)floor(pos);
    hi = (int)ceil(pos);
    frac = pos - lo;
    v = tmp[lo] * (1.0 - frac) + tmp[hi] * frac;
    free(tmp);
    return v;
}

static void preprocess_current(const uint16_t frame[N], const uint16_t bg[N],
                               double out[N])
{
    double buf[W > H ? W : H];
    int x, y, i;
    for (i = 0; i < N; i++)
        out[i] = (double)bg[i] - frame[i];
    for (y = 0; y < H; y++) {
        double m;
        for (x = 0; x < W; x++) buf[x] = out[y*W+x];
        qsort(buf, W, sizeof(double), cmp_double);
        m = buf[W/2];
        for (x = 0; x < W; x++) out[y*W+x] -= m;
    }
    for (x = 0; x < W; x++) {
        double m;
        for (y = 0; y < H; y++) buf[y] = out[y*W+x];
        qsort(buf, H, sizeof(double), cmp_double);
        m = buf[H/2];
        for (y = 0; y < H; y++) out[y*W+x] -= m;
    }
}

static void preprocess_adapt54(const uint16_t frame[N], const uint16_t bg[N],
                               double out[N])
{
    double d[N], p54;
    int i;
    for (i = 0; i < N; i++) d[i] = (double)frame[i] - bg[i];
    p54 = percentile(d, N, 0.54);
    for (i = 0; i < N; i++) {
        double v = d[i] - p54;
        out[i] = v > 0.0 ? v : 0.0;
    }
}

static GxSiftFeatures *extract(const char *frame_path, const char *bg_path,
                               gboolean adaptive)
{
    uint16_t frame[N], bg[N];
    double img[N];
    if (read_u16le(frame_path, frame) || read_u16le(bg_path, bg))
        return NULL;
    if (adaptive) preprocess_adapt54(frame, bg, img);
    else preprocess_current(frame, bg, img);
    return gx_sift_extract(img, W, H);
}

static int fused_score(GxSiftFeatures **set, int n, int probe)
{
    guint8 *seen;
    int i, score = 0;
    GxSiftFeatures *p = set[probe];

    seen = calloc(p->n ? p->n : 1, 1);
    if (!seen)
        return -1;

    for (i = 0; i < n; i++)
        if (i != probe)
            gx_sift_match_mask(set[i], p, seen);

    for (i = 0; i < (int)p->n; i++)
        score += seen[i] ? 1 : 0;

    free(seen);
    return score;
}

int main(int argc, char **argv)
{
    if (argc == 5) {
        GxSiftFeatures *a_cur, *b_cur, *a_ad, *b_ad;
        int cur, ad;

        a_cur = extract(argv[1], argv[2], FALSE);
        b_cur = extract(argv[3], argv[4], FALSE);
        a_ad = extract(argv[1], argv[2], TRUE);
        b_ad = extract(argv[3], argv[4], TRUE);
        if (!a_cur || !b_cur || !a_ad || !b_ad)
            return 3;
        cur = gx_sift_match(a_cur, b_cur);
        ad = gx_sift_match(a_ad, b_ad);
        printf("A_CURRENT_FEATURES=%u\n", a_cur->n);
        printf("B_CURRENT_FEATURES=%u\n", b_cur->n);
        printf("A_ADAPT54_FEATURES=%u\n", a_ad->n);
        printf("B_ADAPT54_FEATURES=%u\n", b_ad->n);
        printf("CURRENT_MATCH=%d\n", cur);
        printf("ADAPT54_MATCH=%d\n", ad);
        gx_sift_free(a_cur); gx_sift_free(b_cur);
        gx_sift_free(a_ad); gx_sift_free(b_ad);
        return 0;
    }

    if (argc == 9) {
        GxSiftFeatures *cur[4] = {0}, *ad[4] = {0};
        int i, rc = 0;

        for (i = 0; i < 4; i++) {
            cur[i] = extract(argv[1 + 2*i], argv[2 + 2*i], FALSE);
            ad[i] = extract(argv[1 + 2*i], argv[2 + 2*i], TRUE);
            if (!cur[i] || !ad[i]) {
                rc = 3;
                goto out4;
            }
        }

        for (i = 0; i < 4; i++) {
            printf("LOO_PROBE_%d_CURRENT=%d\n", i + 1,
                   fused_score(cur, 4, i));
            printf("LOO_PROBE_%d_ADAPT54=%d\n", i + 1,
                   fused_score(ad, 4, i));
            printf("LOO_PROBE_%d_FEATURES=%u/%u\n", i + 1,
                   cur[i]->n, ad[i]->n);
        }

out4:
        for (i = 0; i < 4; i++) {
            gx_sift_free(cur[i]);
            gx_sift_free(ad[i]);
        }
        return rc;
    }

    if (argc == 11) {
        GxSiftFeatures *tcur[4] = {0}, *tad[4] = {0};
        GxSiftFeatures *pcur = NULL, *pad = NULL;
        guint8 *seen_cur = NULL, *seen_ad = NULL;
        int i, sc_cur = 0, sc_ad = 0, rc = 0;

        for (i = 0; i < 4; i++) {
            tcur[i] = extract(argv[1 + 2*i], argv[2 + 2*i], FALSE);
            tad[i] = extract(argv[1 + 2*i], argv[2 + 2*i], TRUE);
            if (!tcur[i] || !tad[i]) {
                rc = 3;
                goto out5;
            }
        }
        pcur = extract(argv[9], argv[10], FALSE);
        pad = extract(argv[9], argv[10], TRUE);
        if (!pcur || !pad) {
            rc = 3;
            goto out5;
        }

        seen_cur = calloc(pcur->n ? pcur->n : 1, 1);
        seen_ad = calloc(pad->n ? pad->n : 1, 1);
        if (!seen_cur || !seen_ad) {
            rc = 4;
            goto out5;
        }

        for (i = 0; i < 4; i++) {
            gx_sift_match_mask(tcur[i], pcur, seen_cur);
            gx_sift_match_mask(tad[i], pad, seen_ad);
        }
        for (i = 0; i < (int)pcur->n; i++)
            sc_cur += seen_cur[i] ? 1 : 0;
        for (i = 0; i < (int)pad->n; i++)
            sc_ad += seen_ad[i] ? 1 : 0;

        printf("PROBE_CURRENT_FEATURES=%u\n", pcur->n);
        printf("PROBE_ADAPT54_FEATURES=%u\n", pad->n);
        printf("TEMPLATE4_CURRENT_FUSED=%d\n", sc_cur);
        printf("TEMPLATE4_ADAPT54_FUSED=%d\n", sc_ad);

out5:
        free(seen_cur);
        free(seen_ad);
        gx_sift_free(pcur);
        gx_sift_free(pad);
        for (i = 0; i < 4; i++) {
            gx_sift_free(tcur[i]);
            gx_sift_free(tad[i]);
        }
        return rc;
    }

    fprintf(stderr,
            "usage: %s A.bin A.bin.bg B.bin B.bin.bg\n"
            "   or: %s 1.bin 1.bg 2.bin 2.bg 3.bin 3.bg 4.bin 4.bg\n"
            "   or: %s T1 T1.bg T2 T2.bg T3 T3.bg T4 T4.bg P P.bg\n",
            argv[0], argv[0], argv[0]);
    return 2;
}
