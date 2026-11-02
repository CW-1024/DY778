#ifndef DY778_CACHE_POLICY_H
#define DY778_CACHE_POLICY_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <stdlib.h>
#include <ctype.h>
#include <errno.h>

enum { DY778CacheEventNone, DY778CacheEventLaunch = 3, DY778CacheEventReturn = 4 };
static inline int DY778CacheRecordCleanup(int remove, int explicitRequest, uint64_t deletedCount, int failed) {
    return remove && (explicitRequest || deletedCount > 0 || failed);
}
typedef struct { int launched; int backgrounded; } DY778CacheLifecycle;
static inline int DY778CacheActivationEvent(DY778CacheLifecycle *state) {
    if (!state->launched) { state->launched = 1; state->backgrounded = 0; return DY778CacheEventLaunch; }
    if (state->backgrounded) { state->backgrounded = 0; return DY778CacheEventReturn; }
    return DY778CacheEventNone;
}
static inline int DY778CacheEventEnabled(int event, int launch, int foreground) {
    return event == DY778CacheEventLaunch ? launch : event == DY778CacheEventReturn ? foreground : 0;
}
enum { DY778CacheScopeNone, DY778CacheScopeMedia, DY778CacheScopeTemporary, DY778CacheScopeResources, DY778CacheScopeCast, DY778CacheScopeLogs };
enum { DY778CacheKindKeep, DY778CacheKindMedia, DY778CacheKindLog, DY778CacheKindData };

static inline int DY778CacheRootScope(const char *relative) {
    if (!relative) return DY778CacheScopeNone;
    const char *roots[] = {"Library/Caches", "tmp", "Library/Application Support/gurd_cache", "Library/BDByteCast", "Library/kitelog"};
    for (int i = 0; i < 5; i++) if (!strcmp(relative, roots[i])) return i + 1;
    return DY778CacheScopeNone;
}
static inline int DY778CachePluginConfiguration(const char *relative, const char *const *plugins, size_t pluginCount) {
    if (!relative || !*relative || *relative == '/' || strlen(relative) >= 4096) return 1;
    char path[4096]; size_t length = strlen(relative);
    for (size_t i = 0; i <= length; i++) path[i] = (char)tolower((unsigned char)relative[i]);
    if (!strcmp(path, ".") || !strcmp(path, "..") || strstr(path, "../") || strstr(path, "/..")) return 1;
    const char *leaf = strrchr(path, '/'); leaf = leaf ? leaf + 1 : path;
    int owned = strstr(path, "plugin") != NULL || strstr(path, "tweak") != NULL;
    const char *known[] = {"dy778", "chengguang", "dyyy", "yuki", "dylike", "lickingdog", "douyinluckybag", "douyinhelper", "dystorage"};
    for (size_t i = 0; !owned && i < sizeof(known)/sizeof(*known); i++) owned = strstr(path, known[i]) != NULL;
    for (size_t i = 0; !owned && i < pluginCount; i++)
        if (plugins[i] && strlen(plugins[i]) >= 3) owned = strstr(path, plugins[i]) != NULL;
    if (!owned) return 0;
    if (strstr(path, "preferences/") || strstr(path, "settings/") || strstr(path, "config/") ||
        strstr(leaf, "config") || strstr(leaf, "setting") || strstr(leaf, "preference")) return 1;
    const char *extension = strrchr(leaf, '.'); extension = extension ? extension + 1 : "";
    const char *formats[] = {"plist", "json", "yaml", "yml", "toml", "ini", "conf", "cfg", "prefs", "mmkv", "db", "sqlite", "sqlite3"};
    for (size_t i = 0; i < sizeof(formats)/sizeof(*formats); i++) {
        size_t n = strlen(formats[i]);
        if (!strncmp(extension, formats[i], n) && (!extension[n] || extension[n] == '-')) return 1;
    }
    return 0;
}
static inline int DY778CacheSensitivePath(const char *relative) {
    return DY778CachePluginConfiguration(relative, NULL, 0);
}
static inline int DY778CacheFileKind(int scope, const char *relative) {
    if (scope < DY778CacheScopeMedia || scope > DY778CacheScopeLogs || DY778CacheSensitivePath(relative)) return DY778CacheKindKeep;
    return DY778CacheKindData;
}
static inline int DY778CacheIdle(int scope, double newestWrite, double now) {
    return scope >= DY778CacheScopeMedia && scope <= DY778CacheScopeLogs && isfinite(newestWrite) && isfinite(now);
}
static inline uint64_t DY778CacheAddBytes(uint64_t left, uint64_t right) { return right > UINT64_MAX - left ? UINT64_MAX : left + right; }

static inline uint64_t DY778CacheByteLimit(double mb) {
    if (!isfinite(mb) || mb <= 0) return 0;
    long double bytes = (long double)mb * 1048576.0L;
    return bytes >= 18446744073709551616.0L ? UINT64_MAX : (uint64_t)bytes;
}
static inline int DY778CacheShouldDelete(uint64_t total, uint64_t limit, double newestUse, double now, double ageHours) {
    if (!isfinite(newestUse) || !isfinite(now)) return 0;
    int expired = isfinite(ageHours) && ageHours > 0 && (now - newestUse) / 3600.0 >= ageHours;
    return expired || (limit > 0 && total > limit);
}
static inline int DY778CacheDeletionAllowed(int manual, int enabled, int cancelled, int scope,
    uint64_t total, uint64_t limit, double newestWrite, double now, double ageHours) {
    if (manual ? cancelled : !enabled) return 0;
    return DY778CacheIdle(scope, newestWrite, now) && (manual || DY778CacheShouldDelete(total, limit, newestWrite, now, ageHours));
}
static inline int DY778CacheSafeComponent(const char *name) {
    return name && *name && strcmp(name, ".") && strcmp(name, "..") && !strchr(name, '/') && strlen(name) <= 255;
}
static inline int DY778CacheOpenParent(int root, const char *relative, char leaf[256]) {
    if (!relative || !*relative || *relative == '/' || strlen(relative) >= 4096) return -1;
    char path[4096]; memcpy(path, relative, strlen(relative) + 1);
    int parent = dup(root); if (parent < 0) return -1;
    char *cursor = path; unsigned depth = 0;
    for (;;) {
        char *slash = strchr(cursor, '/'); if (slash) *slash = 0;
        if (++depth > 64 || !DY778CacheSafeComponent(cursor)) { close(parent); return -1; }
        if (!slash) { memcpy(leaf, cursor, strlen(cursor) + 1); return parent; }
        int next = openat(parent, cursor, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        close(parent); if (next < 0) return -1; parent = next; cursor = slash + 1;
    }
}
static inline int DY778CacheSameContent(const struct stat *before, const struct stat *now) {
    return S_ISREG(now->st_mode) && now->st_nlink == 1 && before->st_dev == now->st_dev && before->st_ino == now->st_ino &&
        before->st_size == now->st_size && before->st_mtime == now->st_mtime && before->st_ctime == now->st_ctime &&
#ifdef __APPLE__
        before->st_mtimespec.tv_nsec == now->st_mtimespec.tv_nsec && before->st_ctimespec.tv_nsec == now->st_ctimespec.tv_nsec;
#else
        before->st_mtim.tv_nsec == now->st_mtim.tv_nsec && before->st_ctim.tv_nsec == now->st_ctim.tv_nsec;
#endif
}
static inline int DY778CacheSameFile(const struct stat *before, const struct stat *now) {
    return DY778CacheSameContent(before, now) && before->st_atime == now->st_atime &&
#ifdef __APPLE__
        before->st_atimespec.tv_nsec == now->st_atimespec.tv_nsec;
#else
        before->st_atim.tv_nsec == now->st_atim.tv_nsec;
#endif
}
static inline int DY778CacheUnlinkVerified(int root, const char *relative, const struct stat *expected) {
    char leaf[256]; int parent = DY778CacheOpenParent(root, relative, leaf); if (parent < 0) return 0;
    struct stat current; int removed = 0;
    if (!fstatat(parent, leaf, &current, AT_SYMLINK_NOFOLLOW) && DY778CacheSameFile(expected, &current)) removed = unlinkat(parent, leaf, 0) == 0;
    close(parent); return removed;
}
static inline int DY778CacheUnlinkCurrent(int root, const char *relative, const struct stat *expected, uint64_t *bytes) {
    char leaf[256]; int parent = DY778CacheOpenParent(root, relative, leaf); if (parent < 0) return 0;
    struct stat current; int removed = 0;
    if (!fstatat(parent, leaf, &current, AT_SYMLINK_NOFOLLOW) && S_ISREG(current.st_mode) &&
        current.st_dev == expected->st_dev && current.st_ino == expected->st_ino) {
        removed = unlinkat(parent, leaf, 0) == 0;
        if (removed && bytes) *bytes = current.st_size > 0 ? (uint64_t)current.st_size : 0;
    }
    close(parent); return removed;
}

typedef struct { DIR *directory; char relative[4096]; } DY778CacheWalkFrame;
typedef struct { DY778CacheWalkFrame *frames; size_t depth; int incomplete; int pruneEmpty; } DY778CacheWalker;
typedef int (*DY778CacheWalkFilter)(const char *, int, void *);
static inline void DY778CacheWalkClose(DY778CacheWalker *walk) {
    if (walk->frames) { for (size_t i = 0; i < walk->depth; i++) if (walk->frames[i].directory) closedir(walk->frames[i].directory); free(walk->frames); }
    walk->frames = NULL; walk->depth = 0;
}
static inline int DY778CacheWalkStart(DY778CacheWalker *walk, int root) {
    DY778CacheWalkClose(walk); walk->incomplete = 0;
    walk->frames = calloc(64, sizeof(DY778CacheWalkFrame)); if (!walk->frames) return 0;
    int copy = openat(root, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC); if (copy < 0) { DY778CacheWalkClose(walk); return 0; }
    walk->frames[0].directory = fdopendir(copy);
    if (!walk->frames[0].directory) { close(copy); DY778CacheWalkClose(walk); return 0; }
    walk->depth = 1; return 1;
}
// One readdir step per call lets callers yield without losing directory offsets.
// 0 = finished, 1 = ordinary file, 2 = directory/filtered entry.
static inline int DY778CacheWalkNext(DY778CacheWalker *walk, DY778CacheWalkFilter filter, void *context,
    char relative[4096], struct stat *snapshot, int *parent) {
    if (!walk->depth) return 0;
    DY778CacheWalkFrame *frame = &walk->frames[walk->depth - 1];
    errno = 0; struct dirent *entry = readdir(frame->directory);
    if (!entry) {
        if (errno) walk->incomplete = 1;
        else if (walk->pruneEmpty && walk->depth > 1) {
            const char *leaf = strrchr(frame->relative, '/'); leaf = leaf ? leaf + 1 : frame->relative;
            int ancestor = dirfd(walk->frames[walk->depth - 2].directory); struct stat actual, opened;
            if (!fstat(dirfd(frame->directory), &opened) && !fstatat(ancestor, leaf, &actual, AT_SYMLINK_NOFOLLOW) &&
                S_ISDIR(actual.st_mode) && actual.st_ino == opened.st_ino && actual.st_dev == opened.st_dev)
                unlinkat(ancestor, leaf, AT_REMOVEDIR);
        }
        closedir(frame->directory); frame->directory = NULL; walk->depth--; return walk->depth ? 2 : 0;
    }
    if (!DY778CacheSafeComponent(entry->d_name)) return 2;
    int directory = dirfd(frame->directory);
    if (fstatat(directory, entry->d_name, snapshot, AT_SYMLINK_NOFOLLOW)) { if (errno != ENOENT) walk->incomplete = 1; return 2; }
    int isDirectory = S_ISDIR(snapshot->st_mode);
    if ((!isDirectory && !S_ISREG(snapshot->st_mode)) || (filter && !filter(entry->d_name, isDirectory, context))) return 2;
    size_t prefix = strlen(frame->relative), nameLength = strlen(entry->d_name);
    if (prefix + nameLength + 2 > 4096) { walk->incomplete = 1; return 2; }
    memcpy(relative, frame->relative, prefix);
    if (prefix) relative[prefix++] = '/';
    memcpy(relative + prefix, entry->d_name, nameLength + 1);
    if (isDirectory) {
        if (walk->depth >= 64) { walk->incomplete = 1; return 2; }
        int child = openat(directory, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (child < 0) { walk->incomplete = 1; return 2; }
        DIR *stream = fdopendir(child); if (!stream) { close(child); walk->incomplete = 1; return 2; }
        DY778CacheWalkFrame *next = &walk->frames[walk->depth++]; next->directory = stream; memcpy(next->relative, relative, strlen(relative) + 1); return 2;
    }
    *parent = directory; return 1;
}
#endif
