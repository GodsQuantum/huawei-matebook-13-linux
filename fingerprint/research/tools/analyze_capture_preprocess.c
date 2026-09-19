#define _GNU_SOURCE
#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

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
    if (fclose(f) != 0 || n != sizeof buf) {
        fprintf(stderr, "invalid capture size for %s: got %zu expected %zu\n",
                path, n, sizeof buf);
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

    if (!tmp)
        return 0.0;
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

static double stddev(const double *a, int n)
{
    double m = 0.0, v = 0.0;
    int i;

    for (i = 0; i < n; i++)
        m += a[i];
    m /= n;
    for (i = 0; i < n; i++) {
        const double d = a[i] - m;
        v += d * d;
    }
    return sqrt(v / n);
}

/* Byte-for-byte equivalent math to gx_preprocess(): bg-frame, row median,
 * then column median. */
static void preprocess_current(const uint16_t frame[N], const uint16_t bg[N],
                               double out[N])
{
    double buf[W > H ? W : H];
    int x, y, i;

    for (i = 0; i < N; i++)
        out[i] = (double)bg[i] - frame[i];

    for (y = 0; y < H; y++) {
        double m;
        for (x = 0; x < W; x++)
            buf[x] = out[y * W + x];
        qsort(buf, W, sizeof(double), cmp_double);
        m = buf[W / 2];
        for (x = 0; x < W; x++)
            out[y * W + x] -= m;
    }
    for (x = 0; x < W; x++) {
        double m;
        for (y = 0; y < H; y++)
            buf[y] = out[y * W + x];
        qsort(buf, H, sizeof(double), cmp_double);
        m = buf[H / 2];
        for (y = 0; y < H; y++)
            out[y * W + x] -= m;
    }
}

/* Public GXFP51A0 imaging finding: d=frame-bg, remove drifting DC from the
 * ~54th percentile, clip negative values. Scaling is irrelevant to RootSIFT. */
static double preprocess_adapt54(const uint16_t frame[N], const uint16_t bg[N],
                                 double out[N])
{
    double d[N];
    double p54;
    int i;

    for (i = 0; i < N; i++)
        d[i] = (double)frame[i] - bg[i];
    p54 = percentile(d, N, 0.54);
    for (i = 0; i < N; i++) {
        const double v = d[i] - p54;
        out[i] = v > 0.0 ? v : 0.0;
    }
    return p54;
}

static void print_feature_geometry(const char *prefix, const GxSiftFeatures *f)
{
    int minx = W, miny = H, maxx = -1, maxy = -1;
    int grid[4][4] = {{0}};
    int occupied = 0;
    guint i;

    if (!f || !f->n) {
        printf("%s_BBOX=none\n", prefix);
        printf("%s_GRID4_OCCUPIED=0/16\n", prefix);
        return;
    }

    for (i = 0; i < f->n; i++) {
        int x = f->pts[i].x, y = f->pts[i].y;
        int gx = x * 4 / W, gy = y * 4 / H;
        if (x < minx) minx = x;
        if (x > maxx) maxx = x;
        if (y < miny) miny = y;
        if (y > maxy) maxy = y;
        if (gx < 0) gx = 0; else if (gx > 3) gx = 3;
        if (gy < 0) gy = 0; else if (gy > 3) gy = 3;
        grid[gy][gx]++;
    }

    for (int gy = 0; gy < 4; gy++)
        for (int gx = 0; gx < 4; gx++)
            if (grid[gy][gx])
                occupied++;

    printf("%s_BBOX=%d,%d-%d,%d\n", prefix, minx, miny, maxx, maxy);
    printf("%s_BBOX_AREA_PCT=%.3f\n", prefix,
           100.0 * (maxx - minx + 1) * (maxy - miny + 1) / (W * H));
    printf("%s_GRID4_OCCUPIED=%d/16\n", prefix, occupied);
}

static int write_pgm(const char *path, const double img[N])
{
    double lo = percentile(img, N, 0.01);
    double hi = percentile(img, N, 0.99);
    FILE *f;
    int i;

    if (hi <= lo)
        hi = lo + 1.0;
    f = fopen(path, "wb");
    if (!f)
        return -1;
    fprintf(f, "P5\n%d %d\n255\n", W, H);
    for (i = 0; i < N; i++) {
        double z = (img[i] - lo) * 255.0 / (hi - lo);
        unsigned char p = (unsigned char)(z < 0 ? 0 : z > 255 ? 255 : z);
        if (fwrite(&p, 1, 1, f) != 1) {
            fclose(f);
            return -1;
        }
    }
    if (fclose(f) != 0)
        return -1;
    chmod(path, 0600);
    return 0;
}

int main(int argc, char **argv)
{
    uint16_t frame[N], bg[N];
    double cur[N], adapt[N], diff[N];
    GxSiftFeatures *fc = NULL, *fa = NULL;
    double p54;
    int i, clipped = 0;
    char pgm_cur[4096], pgm_adapt[4096];

    if (argc != 4) {
        fprintf(stderr, "usage: %s FRAME.bin FRAME.bin.bg OUTPUT_DIR\n", argv[0]);
        return 2;
    }
    umask(077);
    if (read_u16le(argv[1], frame) || read_u16le(argv[2], bg))
        return 3;

    for (i = 0; i < N; i++)
        diff[i] = (double)frame[i] - bg[i];

    preprocess_current(frame, bg, cur);
    p54 = preprocess_adapt54(frame, bg, adapt);
    for (i = 0; i < N; i++)
        if (adapt[i] <= 0.0)
            clipped++;

    fc = gx_sift_extract(cur, W, H);
    fa = gx_sift_extract(adapt, W, H);

    printf("FRAME_BYTES=%d\n", N * 2);
    printf("GEOMETRY=%dx%d\n", W, H);
    printf("DIFF_FRAME_MINUS_BG_MEAN=%.3f\n",
           ({ double s=0; for (i=0;i<N;i++) s+=diff[i]; s/N; }));
    printf("DIFF_FRAME_MINUS_BG_STD=%.3f\n", stddev(diff, N));
    printf("ADAPT54_PERCENTILE=%.3f\n", p54);
    printf("ADAPT54_CLIPPED_PCT=%.3f\n", 100.0 * clipped / N);
    printf("CURRENT_PREPROCESS_STD=%.3f\n", stddev(cur, N));
    printf("ADAPT54_PREPROCESS_STD=%.3f\n", stddev(adapt, N));
    printf("CURRENT_FEATURES=%u\n", fc ? fc->n : 0);
    printf("ADAPT54_FEATURES=%u\n", fa ? fa->n : 0);
    print_feature_geometry("CURRENT", fc);
    print_feature_geometry("ADAPT54", fa);
    printf("CURRENT_VS_ADAPT54_MATCH=%d\n", gx_sift_match(fc, fa));

    snprintf(pgm_cur, sizeof pgm_cur, "%s/preview-current.pgm", argv[3]);
    snprintf(pgm_adapt, sizeof pgm_adapt, "%s/preview-adaptive54.pgm", argv[3]);
    if (write_pgm(pgm_cur, cur) || write_pgm(pgm_adapt, adapt)) {
        fprintf(stderr, "failed to write private PGM previews\n");
        gx_sift_free(fc);
        gx_sift_free(fa);
        return 4;
    }
    printf("PREVIEW_CURRENT=%s\n", pgm_cur);
    printf("PREVIEW_ADAPT54=%s\n", pgm_adapt);

    gx_sift_free(fc);
    gx_sift_free(fa);
    return 0;
}
