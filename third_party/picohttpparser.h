#ifndef FIBER_PICOHTTPPARSER_H
#define FIBER_PICOHTTPPARSER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct phr_header {
    const char* name;
    size_t name_len;
    const char* value;
    size_t value_len;
} phr_header;

int phr_parse_request(const char* buf, size_t len,
                      const char** method, size_t* method_len,
                      const char** path, size_t* path_len,
                      int* minor_version, phr_header* headers,
                      size_t* num_headers, size_t last_len);

#ifdef __cplusplus
}
#endif

#endif
