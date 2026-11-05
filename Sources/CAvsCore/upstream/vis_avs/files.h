#pragma once

#include <stddef.h>

/* Search for files matching `pattern` recursively in `path`. If `background` is `false`
 * then `callback_data_size` can be 0, even if `callback_data` is used.*/
void find_files_by_extensions(const char* path,
                              const char* const* extensions,
                              int num_extensions,
                              void (*callback)(const char* file, void* data),
                              void* callback_data,
                              size_t callback_data_size,
                              bool recursive = false,
                              bool background = false);
