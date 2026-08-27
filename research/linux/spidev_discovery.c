#define _POSIX_C_SOURCE 200809L
#include "spidev_discovery.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static int is_spidev_name(const char *name)
{
    const char *p;
    int seen_major = 0;
    int seen_minor = 0;

    if (strncmp(name, "spidev", 6) != 0)
        return 0;

    p = name + 6;
    while (isdigit((unsigned char)*p)) {
        seen_major = 1;
        p++;
    }
    if (!seen_major || *p != '.')
        return 0;
    p++;
    while (isdigit((unsigned char)*p)) {
        seen_minor = 1;
        p++;
    }
    return seen_minor && *p == '\0';
}

enum gxfp_discovery_result
gxfp_find_spidev_node(const char *spi_sysfs_dir,
                      const char *dev_root,
                      char *out_path,
                      size_t out_size)
{
    DIR *dir;
    struct dirent *entry;
    char spidev_dir[4096];
    char match[256] = {0};
    unsigned matches = 0;
    int n;

    if (!spi_sysfs_dir || !*spi_sysfs_dir || !dev_root || !*dev_root ||
        !out_path || out_size == 0)
        return GXFP_DISCOVERY_INVALID;

    n = snprintf(spidev_dir, sizeof(spidev_dir), "%s/spidev", spi_sysfs_dir);
    if (n < 0 || (size_t)n >= sizeof(spidev_dir))
        return GXFP_DISCOVERY_PATH_TOO_LONG;

    dir = opendir(spidev_dir);
    if (!dir)
        return GXFP_DISCOVERY_IO_ERROR;

    while ((entry = readdir(dir)) != NULL) {
        if (!is_spidev_name(entry->d_name))
            continue;
        matches++;
        if (matches == 1) {
            n = snprintf(match, sizeof(match), "%s", entry->d_name);
            if (n < 0 || (size_t)n >= sizeof(match)) {
                closedir(dir);
                return GXFP_DISCOVERY_PATH_TOO_LONG;
            }
        }
    }

    if (closedir(dir) != 0)
        return GXFP_DISCOVERY_IO_ERROR;

    if (matches == 0)
        return GXFP_DISCOVERY_NOT_FOUND;
    if (matches > 1)
        return GXFP_DISCOVERY_AMBIGUOUS;

    n = snprintf(out_path, out_size, "%s/%s", dev_root, match);
    if (n < 0 || (size_t)n >= out_size)
        return GXFP_DISCOVERY_PATH_TOO_LONG;

    {
        struct stat st;
        if (stat(out_path, &st) != 0)
            return errno == ENOENT ? GXFP_DISCOVERY_NOT_FOUND
                                   : GXFP_DISCOVERY_IO_ERROR;
    }

    return GXFP_DISCOVERY_OK;
}
