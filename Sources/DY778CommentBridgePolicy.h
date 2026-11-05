#ifndef DY778_COMMENT_BRIDGE_POLICY_H
#define DY778_COMMENT_BRIDGE_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

static inline bool DY778CommentVerifiedVersion(const char *version) {
    return version && (!strcmp(version,"39.9.0") || !strcmp(version,"39.9"));
}
static inline bool DY778CommentSlotValid(ptrdiff_t offset, size_t instanceSize,
                                         size_t fieldSize, size_t alignment) {
    return offset >= (ptrdiff_t)sizeof(void *) && alignment > 0 && fieldSize > 0 &&
           (size_t)offset % alignment == 0 && (size_t)offset <= instanceSize &&
           fieldSize <= instanceSize - (size_t)offset;
}
#endif
