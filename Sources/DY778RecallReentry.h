#ifndef DY778_RECALL_REENTRY_H
#define DY778_RECALL_REENTRY_H
#include <stdbool.h>
typedef struct DY778RecallFrame {
    const void *object;
    unsigned int operation;
    struct DY778RecallFrame *previous;
} DY778RecallFrame;
enum { DY778RecallReadContent = 1, DY778RecallReadFlag, DY778RecallWriteContent,
       DY778RecallWriteFlag, DY778RecallWriteOriginal, DY778RecallApply, DY778RecallApplyV2, DY778RecallWriteEdit };
static inline bool DY778RecallFrameContains(const DY778RecallFrame *frame, const void *object, unsigned int operation) {
    for (; frame; frame = frame->previous)
        if (frame->object == object && frame->operation == operation) return true;
    return false;
}
static inline bool DY778RecallFrameIsMutating(const DY778RecallFrame *frame, const void *object) {
    for (; frame; frame = frame->previous)
        if (frame->object == object && frame->operation >= DY778RecallWriteContent) return true;
    return false;
}
#endif
