#include "../../driver/goodix51a0/gx51_transport.h"

#include <assert.h>
#include <stdio.h>

int main(void)
{
    assert(GX51_SPI_READ_CHUNK_MAX == 4096u);
    assert(gx51_read_chunk_size(0u) == 0u);
    assert(gx51_read_chunk_size(1u) == 1u);
    assert(gx51_read_chunk_size(4096u) == 4096u);
    assert(gx51_read_chunk_size(4097u) == 4096u);
    assert(gx51_read_chunk_size(10602u) == 4096u);
    puts("test_transport_chunking: OK");
    return 0;
}
