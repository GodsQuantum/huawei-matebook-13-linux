#define _POSIX_C_SOURCE 200809L
#include "linux/spidev_discovery.h"

#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

static void must_mkdir(const char *path)
{
    if (mkdir(path, 0700) != 0 && errno != EEXIST) {
        perror(path);
        abort();
    }
}

static void make_case_root(char root[PATH_MAX])
{
    const char *tmp = getenv("TMPDIR");
    int n;

    assert(tmp && *tmp);
    n = snprintf(root, PATH_MAX, "%s/gxfp-disc-XXXXXX", tmp);
    assert(n > 0 && n < PATH_MAX);
    assert(mkdtemp(root));
}

static void make_spidev_dir(const char *root, const char *name)
{
    char path[PATH_MAX];
    int n = snprintf(path, sizeof(path), "%s/spidev/%s", root, name);
    assert(n > 0 && (size_t)n < sizeof(path));
    must_mkdir(path);
}

static void setup_root(const char *root)
{
    char path[PATH_MAX];
    int n = snprintf(path, sizeof(path), "%s/spidev", root);
    assert(n > 0 && (size_t)n < sizeof(path));
    must_mkdir(path);
}

static void setup_dev_root(const char *root, char dev_root[PATH_MAX])
{
    int n = snprintf(dev_root, PATH_MAX, "%s/dev", root);
    assert(n > 0 && n < PATH_MAX);
    must_mkdir(dev_root);
}

static void make_dev_node(const char *dev_root, const char *name)
{
    char path[PATH_MAX];
    FILE *f;
    int n = snprintf(path, sizeof(path), "%s/%s", dev_root, name);
    assert(n > 0 && (size_t)n < sizeof(path));
    f = fopen(path, "wb");
    assert(f);
    assert(fclose(f) == 0);
}

static void test_exactly_one(void)
{
    char root[PATH_MAX];
    char out[PATH_MAX];
    char dev_root[PATH_MAX];
    char expected[PATH_MAX];
    make_case_root(root);
    setup_root(root);
    setup_dev_root(root, dev_root);
    make_spidev_dir(root, "spidev1.0");
    make_dev_node(dev_root, "spidev1.0");

    assert(gxfp_find_spidev_node(root, dev_root, out, sizeof(out)) == GXFP_DISCOVERY_OK);
    assert(snprintf(expected, sizeof(expected), "%s/spidev1.0", dev_root) > 0);
    assert(strcmp(out, expected) == 0);
}

static void test_zero(void)
{
    char root[PATH_MAX];
    char out[PATH_MAX];
    char dev_root[PATH_MAX];
    make_case_root(root);
    setup_root(root);
    setup_dev_root(root, dev_root);
    assert(gxfp_find_spidev_node(root, dev_root, out, sizeof(out)) == GXFP_DISCOVERY_NOT_FOUND);
}

static void test_multiple(void)
{
    char root[PATH_MAX];
    char out[PATH_MAX];
    char dev_root[PATH_MAX];
    make_case_root(root);
    setup_root(root);
    setup_dev_root(root, dev_root);
    make_spidev_dir(root, "spidev1.0");
    make_spidev_dir(root, "spidev2.0");
    assert(gxfp_find_spidev_node(root, dev_root, out, sizeof(out)) == GXFP_DISCOVERY_AMBIGUOUS);
}

static void test_ignores_unrelated(void)
{
    char root[PATH_MAX];
    char out[PATH_MAX];
    char dev_root[PATH_MAX];
    char expected[PATH_MAX];
    make_case_root(root);
    setup_root(root);
    setup_dev_root(root, dev_root);
    make_spidev_dir(root, "not-spidev");
    make_spidev_dir(root, "spidevX.Y");
    make_spidev_dir(root, "spidev3.4");
    make_dev_node(dev_root, "spidev3.4");
    assert(gxfp_find_spidev_node(root, dev_root, out, sizeof(out)) == GXFP_DISCOVERY_OK);
    assert(snprintf(expected, sizeof(expected), "%s/spidev3.4", dev_root) > 0);
    assert(strcmp(out, expected) == 0);
}

static void test_too_small(void)
{
    char root[PATH_MAX];
    char out[8];
    char dev_root[PATH_MAX];
    make_case_root(root);
    setup_root(root);
    setup_dev_root(root, dev_root);
    make_spidev_dir(root, "spidev1.0");
    make_dev_node(dev_root, "spidev1.0");
    assert(gxfp_find_spidev_node(root, dev_root, out, sizeof(out)) == GXFP_DISCOVERY_PATH_TOO_LONG);
}

static void test_sysfs_child_without_dev_node(void)
{
    char root[PATH_MAX];
    char out[PATH_MAX];
    char dev_root[PATH_MAX];
    make_case_root(root);
    setup_root(root);
    setup_dev_root(root, dev_root);
    make_spidev_dir(root, "spidev1.0");

    assert(gxfp_find_spidev_node(root, dev_root, out, sizeof(out)) == GXFP_DISCOVERY_NOT_FOUND);
}

int main(void)
{
    test_exactly_one();
    test_zero();
    test_multiple();
    test_ignores_unrelated();
    test_too_small();
    test_sysfs_child_without_dev_node();
    puts("test_spidev_discovery: OK");
    return 0;
}
