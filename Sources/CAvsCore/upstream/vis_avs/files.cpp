#include "files.h"
#include "constants.h"  // NullPlayer: MAX_PATH, otherwise only defined in the __linux__ block

#include <cstring>
#include <string>
#include <thread>

#if defined(__linux__) && !defined(FORCE_CPP_FILESYSTEM_API)
#include <ftw.h>
#include <glob.h>
#elif defined(_WIN32) && !defined(FORCE_CPP_FILESYSTEM_API)
#include <windows.h>
#endif

#if defined(FORCE_CPP_FILESYSTEM_API) && __cplusplus >= 201703L
#include <filesystem>
namespace fs = std::filesystem;
#endif

bool matches_file_suffix(const std::string& file,
                         const char* const* suffixes,
                         int num_suffixes) {
    for (int i = 0; i < num_suffixes; i++) {
        size_t suffix_length = strnlen(suffixes[i], 32);
        if (file.substr(file.length() - suffix_length, suffix_length) == suffixes[i]) {
            return true;
        }
    }
    return false;
}

#if defined(__linux__) && !defined(FORCE_CPP_FILESYSTEM_API)
/* This whole ftw() section is a bit confusing. The gist of it is that you call `ftw()`
 * which will walk a filesystem subtree for you, with the help of a callback function
 * that you give it. (This is the function `ftw_callback()` below.) So far so easy.
 *
 * The tricky part is that the ftw callback function cannot have user data passed to it.
 * So in order to map the callback to `find_files_with_extensions()` (which has user
 * data) to the `ftw()` callback, we need to use a global variable that you can use in
 * the callback. Now we have two nested callbacks, an outer one mandated by `ftw()`, and
 * an inner one, given by the user of `find_files_by_extensions()`.
 *
 * So before calling `ftw()` proper, we set the global `ftw_data` variable that contains
 * the user callback data as well as the list of extensions that
 * `find_files_by_extensions()` should match against.
 *
 * To top it off, we _only_ use this for the `recursive=true` mode on linux.
 * But it _is_ very fast.
 */

#define MAX_PATH              260
// The maximum number of open file descriptors allowed for `ftw()` is roughly correlated
// to the expected depth of the file subtree. 15 seems more than enough. If the tree is
// deeper nothing bad will happen, `ftw()` will just get slower.
#define FIND_FTW_MAX_OPEN_FDS 15
typedef struct {
    const char* const* extensions;
    int num_extensions;
    void (*callback)(const char* file, void* data);
    void* callback_data;
} ftw_data_t;

// "thread_local" makes a new instance of this variable for each thread. This should™
// make this whole construct thread-safe.
static thread_local ftw_data_t ftw_data;

int ftw_callback(const char* file_path, const struct stat* file_info, int file_type) {
    if (file_type == FTW_F
        && matches_file_suffix(
            std::string(file_path), ftw_data.extensions, ftw_data.num_extensions)) {
        ftw_data.callback(file_path, ftw_data.callback_data);
    }
    return 0;
}
#endif  // __linux__

#ifdef _WIN32
void win32_find_files_by_extensions(const char* path,
                                    const char* partial_path,
                                    const char* const* extensions,
                                    int num_extensions,
                                    void (*callback)(const char* file, void* data),
                                    void* callback_data,
                                    bool recursive) {
    WIN32_FIND_DATA find_info;
    HANDLE find_handle;
    char wildcard_path[MAX_PATH];
    char new_partial_path[MAX_PATH];

    for (int ext = 0; ext < num_extensions; ext++) {
        strncpy(wildcard_path, path, MAX_PATH - 1);
        strcat(wildcard_path, "*");
        strncat(wildcard_path, extensions[ext], MAX_PATH - 1);
        find_handle = FindFirstFile(wildcard_path, &find_info);
        if (find_handle == INVALID_HANDLE_VALUE) {
            continue;
        }
        do {
            strcpy(new_partial_path, partial_path);
            strcat(new_partial_path, find_info.cFileName);
            callback(new_partial_path, callback_data);
        } while (FindNextFile(find_handle, &find_info));
        FindClose(find_handle);
    }

    if (recursive) {
        char new_full_path[MAX_PATH];
        strncpy(wildcard_path, path, MAX_PATH - 1);
        strcat(wildcard_path, "*");
        find_handle = FindFirstFileEx(wildcard_path,
                                      FindExInfoBasic,
                                      &find_info,
                                      FindExSearchLimitToDirectories,
                                      NULL,
                                      0);
        if (find_handle != INVALID_HANDLE_VALUE) {
            do {
                if (find_info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY
                    && strstr(find_info.cFileName, ".") == 0) {
                    strcpy(new_full_path, path);
                    strcat(new_full_path, find_info.cFileName);
                    strcat(new_full_path, "/");
                    strcpy(new_partial_path, partial_path);
                    strcat(new_partial_path, find_info.cFileName);
                    strcat(new_partial_path, "/");
                    win32_find_files_by_extensions(new_full_path,
                                                   new_partial_path,
                                                   extensions,
                                                   num_extensions,
                                                   callback,
                                                   callback_data,
                                                   recursive);
                }
            } while (FindNextFile(find_handle, &find_info));
        }
    }
}
#endif  // WIN32

void find_files_by_extensions_(const char* path,
                               const char* const* extensions,
                               int num_extensions,
                               void (*callback)(const char* file, void* data),
                               void* callback_data,
                               bool recursive) {
#if defined(__linux__) && !defined(FORCE_CPP_FILESYSTEM_API)

    if (recursive) {
        ftw_data = ftw_data_t{extensions, num_extensions, callback, callback_data};
        ftw(path, ftw_callback, /*max open FDs*/ FIND_FTW_MAX_OPEN_FDS);
    } else {
        char wildcard_path[MAX_PATH];
        bool is_first_glob_call = true;
        glob_t glob_info;
        for (int ext = 0; ext < num_extensions; ext++) {
            strncpy(wildcard_path, path, MAX_PATH - 1);
            strcat(wildcard_path, "/*");
            strcat(wildcard_path, extensions[ext]);
            glob(wildcard_path,
                 is_first_glob_call ? 0 : GLOB_APPEND,
                 nullptr,
                 &glob_info);
            is_first_glob_call = false;
        }
        size_t path_length = strnlen(path, MAX_PATH - 1);
        for (size_t i = 0; i < glob_info.gl_pathc; i++) {
            // remove path + "/" from the front of the filepath
            callback(glob_info.gl_pathv[i] + path_length + 1, callback_data);
        }
        globfree(&glob_info);
    }

#elif defined(_WIN32) && !defined(FORCE_CPP_FILESYSTEM_API)

    char new_path[MAX_PATH];
    strcpy(new_path, path);
    strcat(new_path, "/");
    win32_find_files_by_extensions(
        new_path, "", extensions, num_extensions, callback, callback_data, recursive);

#elif __cplusplus >= 201703L

    auto base_path = fs::path(path);
    if (recursive) {
        for (auto& entry : fs::recursive_directory_iterator(path)) {
            auto path_str = entry.path().string();
            if (matches_file_suffix(path_str, extensions, num_extensions)) {
                callback(fs::relative(entry.path(), base_path).string().c_str(),
                         callback_data);
            }
        }
    } else {
        for (auto& entry : fs::directory_iterator(path)) {
            auto path_str = entry.path().string();
            if (matches_file_suffix(path_str, extensions, num_extensions)) {
                callback(fs::relative(entry.path(), base_path).string().c_str(),
                         callback_data);
            }
        }
    }

#else

#error Need POSIX, Win32 API, or C++17 support for find_files_by_extensions()

#endif
}

/**
 * Just calls `find_files_by_extensions_()` but frees `path`, `extensions` &
 * `callback_data` after the call. Thus, `path` and `extensions` aren't `const` in this
 * version.
 */
void find_files_by_extensions_background(char* path,
                                         char** extensions,
                                         int num_extensions,
                                         void (*callback)(const char* file, void* data),
                                         void* callback_data,
                                         bool recursive) {
    find_files_by_extensions_(
        path, extensions, num_extensions, callback, callback_data, recursive);
    free(callback_data);
    for (int i = 0; i < num_extensions; i++) {
        free(extensions[i]);
    }
    free(extensions);
    free(path);
}

void find_files_by_extensions(const char* path,
                              const char* const* extensions,
                              int num_extensions,
                              void (*callback)(const char* file, void* data),
                              void* callback_data,
                              size_t callback_data_size,
                              bool recursive,
                              bool background) {
    if (!background) {
        find_files_by_extensions_(
            path, extensions, num_extensions, callback, callback_data, recursive);
    } else {
        /* Make copies of the non-scalar parameters, the actual find_files_by_extensions
         * method frees them at the end. */
        size_t path_length = strnlen(path, MAX_PATH - 1);
        char* new_path = (char*)calloc(path_length + 1, sizeof(char));
        strncpy(new_path, path, path_length + 1);
        char** new_extensions = (char**)calloc(num_extensions, sizeof(char*));
        for (int i = 0; i < num_extensions; i++) {
            size_t ext_length = strnlen(extensions[i], MAX_PATH - 1);
            new_extensions[i] = (char*)calloc(ext_length + 1, sizeof(char));
            strncpy(new_extensions[i], extensions[i], ext_length + 1);
        }
        void* new_callback_data = calloc(callback_data_size, 1);
        memcpy(new_callback_data, callback_data, callback_data_size);
        std::thread finder(find_files_by_extensions_background,
                           new_path,
                           new_extensions,
                           num_extensions,
                           callback,
                           new_callback_data,
                           recursive);
        finder.detach();
    }
}
