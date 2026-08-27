#ifndef GXFP_SPIDEV_DISCOVERY_H
#define GXFP_SPIDEV_DISCOVERY_H

#include <stddef.h>

enum gxfp_discovery_result {
    GXFP_DISCOVERY_OK = 0,
    GXFP_DISCOVERY_INVALID,
    GXFP_DISCOVERY_NOT_FOUND,
    GXFP_DISCOVERY_AMBIGUOUS,
    GXFP_DISCOVERY_IO_ERROR,
    GXFP_DISCOVERY_PATH_TOO_LONG,
};

enum gxfp_discovery_result
gxfp_find_spidev_node(const char *spi_sysfs_dir,
                      const char *dev_root,
                      char *out_path,
                      size_t out_size);

#endif
