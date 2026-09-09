#include "picohttpparser.h"

#include <ctype.h>
#include <string.h>

static const char* find_crlf(const char* begin, const char* end) {
    for (const char* cursor = begin; cursor + 1 < end; ++cursor) {
        if (cursor[0] == '\r' && cursor[1] == '\n') {
            return cursor;
        }
    }
    return NULL;
}

static int token_char(unsigned char value) {
    return isalnum(value) || value == '-' || value == '_' || value == '.';
}

int phr_parse_request(const char* buf, size_t len,
                      const char** method, size_t* method_len,
                      const char** path, size_t* path_len,
                      int* minor_version, phr_header* headers,
                      size_t* num_headers, size_t last_len) {
    (void)last_len;
    const char* end = buf + len;
    const char* line_end = find_crlf(buf, end);
    if (line_end == NULL) {
        return -2;
    }

    const char* first_space = (const char*)memchr(buf, ' ', (size_t)(line_end - buf));
    if (first_space == NULL || first_space == buf) {
        return -1;
    }
    const char* second_space = (const char*)memchr(first_space + 1, ' ',
                                                    (size_t)(line_end - first_space - 1));
    if (second_space == NULL || second_space == first_space + 1) {
        return -1;
    }
    if ((size_t)(line_end - second_space) != 9 ||
        memcmp(second_space, " HTTP/1.", 8) != 0 ||
        second_space[8] < '0' || second_space[8] > '9') {
        return -1;
    }

    *method = buf;
    *method_len = (size_t)(first_space - buf);
    *path = first_space + 1;
    *path_len = (size_t)(second_space - first_space - 1);
    *minor_version = second_space[8] - '0';

    size_t count = 0;
    const char* cursor = line_end + 2;
    for (;;) {
        line_end = find_crlf(cursor, end);
        if (line_end == NULL) {
            return -2;
        }
        if (line_end == cursor) {
            *num_headers = count;
            return (int)(cursor + 2 - buf);
        }

        const char* colon = (const char*)memchr(cursor, ':', (size_t)(line_end - cursor));
        if (colon == NULL || colon == cursor || count >= *num_headers) {
            return -1;
        }
        const char* value = colon + 1;
        while (value < line_end && (*value == ' ' || *value == '\t')) {
            ++value;
        }
        const char* value_end = line_end;
        while (value_end > value && (value_end[-1] == ' ' || value_end[-1] == '\t')) {
            --value_end;
        }
        for (const char* name = cursor; name < colon; ++name) {
            if (!token_char((unsigned char)*name)) {
                return -1;
            }
        }
        headers[count].name = cursor;
        headers[count].name_len = (size_t)(colon - cursor);
        headers[count].value = value;
        headers[count].value_len = (size_t)(value_end - value);
        ++count;
        cursor = line_end + 2;
    }
}
