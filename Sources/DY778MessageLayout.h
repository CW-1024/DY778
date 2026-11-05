#ifndef DY778_MESSAGE_LAYOUT_H
#define DY778_MESSAGE_LAYOUT_H
#include <math.h>
#include <stddef.h>

typedef struct { double x, y, width, height; } DY778LayoutRect;
typedef enum { DY778LayoutRight, DY778LayoutAbove, DY778LayoutBelow, DY778LayoutLeft } DY778LayoutPosition;
typedef struct { double width, height; int visible; DY778LayoutPosition position; } DY778LayoutItem;
typedef struct { DY778LayoutRect time, recall; int timeVisible, recallVisible; DY778LayoutPosition timePosition, recallPosition; } DY778MessageLayoutResult;
static inline double DY778LayoutMax(double a, double b) { return a > b ? a : b; }
static inline double DY778LayoutMin(double a, double b) { return a < b ? a : b; }
static inline int DY778LayoutIntersects(DY778LayoutRect a, DY778LayoutRect b) {
    return a.width > 0 && a.height > 0 && b.width > 0 && b.height > 0 &&
        a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
}
static inline int DY778LayoutFits(DY778LayoutRect r, DY778LayoutRect bounds, const DY778LayoutRect *obstacles, size_t count) {
    if (!isfinite(r.x + r.y + r.width + r.height + bounds.x + bounds.y + bounds.width + bounds.height) || bounds.width <= 0 || bounds.height <= 0 || r.width <= 0 || r.height <= 0 ||
        r.x < bounds.x + 4 || r.y < bounds.y + 2 ||
        r.x + r.width > bounds.x + bounds.width - 4 || r.y + r.height > bounds.y + bounds.height - 2) return 0;
    for (size_t i = 0; i < count; i++) if (DY778LayoutIntersects(r, obstacles[i])) return 0;
    return 1;
}
static inline DY778LayoutRect DY778LayoutCandidate(DY778LayoutRect bubble, double width, double height, DY778LayoutPosition position, int outgoing) {
    const double gap = 5;
    DY778LayoutRect r = {bubble.x, bubble.y, width, height};
    if (position == DY778LayoutRight) { r.x = bubble.x + bubble.width + gap; r.y = bubble.y + (bubble.height - height) / 2; }
    else { r.x = outgoing ? bubble.x + bubble.width - width : bubble.x; r.y = position == DY778LayoutAbove ? bubble.y - height - 3 : bubble.y + bubble.height + 3; }
    return r;
}
static inline int DY778LayoutRightColumn(DY778LayoutRect bounds, DY778LayoutRect candidate,
    const DY778LayoutRect *obstacles, size_t count, DY778LayoutRect *result) {
    double minY = bounds.y + 2, maxY = bounds.y + bounds.height - candidate.height - 2;
    if (maxY < minY) return 0;
    candidate.y = DY778LayoutMax(minY, DY778LayoutMin(maxY, candidate.y));
    if (DY778LayoutFits(candidate, bounds, obstacles, count)) { *result = candidate; return 1; }
    double nearest = INFINITY;
    // 整列绕开已有 label 移动；其 x 永不越过气泡。
    for (size_t i = 0; i < count; i++) {
        if (candidate.x >= obstacles[i].x + obstacles[i].width || candidate.x + candidate.width <= obstacles[i].x) continue;
        double edges[2] = {obstacles[i].y - candidate.height - 2, obstacles[i].y + obstacles[i].height + 2};
        for (size_t edge = 0; edge < 2; edge++) {
            DY778LayoutRect shifted = candidate; shifted.y = edges[edge];
            double distance = fabs(shifted.y - candidate.y);
            if (distance < nearest && DY778LayoutFits(shifted, bounds, obstacles, count)) { *result = shifted; nearest = distance; }
        }
    }
    return isfinite(nearest);
}
static inline int DY778LayoutRightPlace(DY778LayoutRect bounds, DY778LayoutRect candidate,
    const DY778LayoutRect *obstacles, size_t count, DY778LayoutRect *result) {
    if (DY778LayoutRightColumn(bounds, candidate, obstacles, count, result)) return 1;
    // 最近的一列可能已被另一插件占用。让我们的两个 label 保持
    // 在一起，并在其右侧尝试一小组有限的列。
    double columns[8]; size_t columnsCount = 0;
    for (size_t i = 0; i < count; i++) {
        double x = obstacles[i].x + obstacles[i].width + 3;
        if (!isfinite(x) || x <= candidate.x || x + candidate.width > bounds.x + bounds.width - 4) continue;
        size_t position = 0;
        while (position < columnsCount && columns[position] < x) position++;
        if (position < columnsCount && columns[position] == x) continue;
        if (position >= 8) continue;
        if (columnsCount < 8) columnsCount++;
        for (size_t j = columnsCount - 1; j > position; j--) columns[j] = columns[j - 1];
        columns[position] = x;
    }
    for (size_t i = 0; i < columnsCount; i++) {
        DY778LayoutRect shifted = candidate; shifted.x = columns[i];
        if (DY778LayoutRightColumn(bounds, shifted, obstacles, count, result)) return 1;
    }
    return 0;
}
static inline int DY778LayoutPlace(DY778LayoutRect bounds, DY778LayoutRect bubble, DY778LayoutItem item, int outgoing,
    const DY778LayoutRect *obstacles, size_t count, DY778LayoutRect *result, DY778LayoutPosition *resolved) {
    if (!isfinite(item.width + item.height) || item.width <= 0 || item.height <= 0) return 0;
    DY778LayoutPosition order[3] = {DY778LayoutRight, DY778LayoutBelow, DY778LayoutAbove};
    if (item.position == DY778LayoutBelow || item.position == DY778LayoutAbove) order[0] = item.position;
    if (item.position == DY778LayoutBelow) { order[1] = DY778LayoutRight; order[2] = DY778LayoutAbove; }
    if (item.position == DY778LayoutAbove) { order[1] = DY778LayoutBelow; order[2] = DY778LayoutRight; }
    for (size_t p = 0; p < 3; p++) {
        DY778LayoutRect r = DY778LayoutCandidate(bubble, item.width, item.height, order[p], outgoing);
        if (order[p] == DY778LayoutRight) {
            if (DY778LayoutRightPlace(bounds, r, obstacles, count, result)) { *resolved = DY778LayoutRight; return 1; }
            continue;
        }
        if (DY778LayoutFits(r, bounds, obstacles, count)) { *result = r; *resolved = order[p]; return 1; }
    }
    return 0;
}
static inline DY778MessageLayoutResult DY778ComputeMessageLayout(DY778LayoutRect bounds, DY778LayoutRect bubble,
    DY778LayoutItem time, DY778LayoutItem recall, int outgoing, const DY778LayoutRect *obstacles, size_t count) {
    DY778MessageLayoutResult result = {0};
    if (count > 128 || (count && !obstacles) || bubble.width <= 0 || bubble.height <= 0 || !isfinite(bubble.x + bubble.y + bubble.width + bubble.height)) return result;
    DY778LayoutRect occupied[131];
    size_t used = 0;
    for (size_t i = 0; i < count; i++) occupied[used++] = obstacles[i];
    occupied[used++] = bubble;
    if (time.visible && recall.visible && time.position == recall.position) {
        DY778LayoutItem group = {DY778LayoutMax(time.width, recall.width), time.height + recall.height + 2, 1, time.position};
        DY778LayoutRect placed;
        DY778LayoutPosition position;
        if (DY778LayoutPlace(bounds, bubble, group, outgoing, occupied, used, &placed, &position)) {
            result.time = (DY778LayoutRect){placed.x, placed.y, time.width, time.height};
            result.recall = (DY778LayoutRect){placed.x, placed.y + time.height + 2, recall.width, recall.height};
            result.timeVisible = result.recallVisible = 1;
            result.timePosition = result.recallPosition = position;
        }
        // 绝不把共享列拆成互不相关的单个 label。
        return result;
    }
    if (time.visible) {
        result.timeVisible = DY778LayoutPlace(bounds, bubble, time, outgoing, occupied, used, &result.time, &result.timePosition);
        if (result.timeVisible) occupied[used++] = result.time;
    }
    if (recall.visible) result.recallVisible = DY778LayoutPlace(bounds, bubble, recall, outgoing, occupied, used, &result.recall, &result.recallPosition);
    return result;
}
// 兜底：把状态放进消息的绘制区域内，绝不放到行外。
static inline DY778LayoutRect DY778StatusFallbackRect(DY778LayoutRect bounds, DY778LayoutRect bubble, double width, double height) {
    DY778LayoutRect empty = {0};
    if (!isfinite(bounds.x + bounds.y + bounds.width + bounds.height + bubble.x + bubble.y + bubble.width + width + height) || bounds.width < 24 || bounds.height < 16 || width <= 0 || height <= 0) return empty;
    width = DY778LayoutMin(width, bounds.width - 8); height = DY778LayoutMin(height, bounds.height - 4);
    return (DY778LayoutRect){DY778LayoutMax(bounds.x + 4, DY778LayoutMin(bubble.x + bubble.width - width, bounds.x + bounds.width - width - 4)),
        DY778LayoutMax(bounds.y + 2, DY778LayoutMin(bubble.y + 2, bounds.y + bounds.height - height - 2)), width, height};
}
// 三个各自配置的装饰项；状态标记优先于时间标签。
typedef struct { DY778LayoutRect frames[3]; int visible[3]; DY778LayoutPosition positions[3]; int statusFallback; } DY778DecorationLayoutResult;
static inline DY778DecorationLayoutResult DY778PlaceDecorations(DY778LayoutRect bounds, DY778LayoutRect bubble,
    const DY778LayoutItem items[3], int outgoing, const DY778LayoutRect *obstacles, size_t count) {
    DY778DecorationLayoutResult result = {0};
    if (count > 128 || (count && !obstacles) || !isfinite(bubble.x + bubble.y + bubble.width + bubble.height) || bubble.width <= 0 || bubble.height <= 0) return result;
    DY778LayoutRect occupied[132]; size_t used = 0;
    for (size_t i = 0; i < count; i++) occupied[used++] = obstacles[i];
    occupied[used++] = bubble;
    int processed[3] = {0}, order[3] = {1, 2, 0};
    for (int priority = 0; priority < 3; priority++) {
        int first = order[priority]; if (processed[first] || !items[first].visible) continue;
        DY778LayoutItem group = {0, 0, 1, items[first].position}; int members[3], total = 0;
        for (int i = 0; i < 3; i++) if (!processed[i] && items[i].visible && items[i].position == group.position) {
            processed[i] = 1; members[total++] = i;
            group.width = DY778LayoutMax(group.width, items[i].width); group.height += items[i].height + (total > 1 ? 2 : 0);
        }
        DY778LayoutRect frame; DY778LayoutPosition position;
        if (!DY778LayoutPlace(bounds, bubble, group, outgoing, occupied, used, &frame, &position)) continue;
        double y = frame.y;
        for (int n = 0; n < total; n++) {
            int i = members[n]; result.frames[i] = (DY778LayoutRect){frame.x, y, items[i].width, items[i].height};
            result.visible[i] = 1; result.positions[i] = position; y += items[i].height + 2;
        }
        occupied[used++] = frame;
    }
    return result;
}
static inline DY778DecorationLayoutResult DY778ComputeDecorationLayout(DY778LayoutRect bounds, DY778LayoutRect bubble,
    DY778LayoutItem time, DY778LayoutItem recall, DY778LayoutItem edit, int outgoing, const DY778LayoutRect *obstacles, size_t count) {
    DY778LayoutItem items[3] = {time, recall, edit};
    DY778DecorationLayoutResult result = {0};
    if (count > 128 || (count && !obstacles)) return result;
    result = DY778PlaceDecorations(bounds, bubble, items, outgoing, obstacles, count);
    if ((recall.visible && !result.visible[1]) || (edit.visible && !result.visible[2])) {
        items[0].visible = 0;
        result = DY778PlaceDecorations(bounds, bubble, items, outgoing, obstacles, count);
    }
    if ((recall.visible && !result.visible[1]) || (edit.visible && !result.visible[2])) {
        // 空间耗尽时，仍让两个安全标记在短行内可读。
        int both = recall.visible && edit.visible;
        int horizontal = both && recall.height + edit.height + 2 > bounds.height - 4;
        double width = both ? (horizontal ? recall.width + edit.width + 4 : DY778LayoutMax(recall.width, edit.width)) : (recall.visible ? recall.width : edit.width);
        double height = both ? (horizontal ? DY778LayoutMax(recall.height, edit.height) : recall.height + edit.height + 2) : (recall.visible ? recall.height : edit.height);
        DY778LayoutRect frame = DY778StatusFallbackRect(bounds, bubble, width, height);
        result.visible[0] = result.visible[1] = result.visible[2] = 0;
        result.statusFallback = 1;
        if (frame.width <= 0 || frame.height <= 0) return result;
        if (!both) { int i = recall.visible ? 1 : 2; result.frames[i] = frame; result.visible[i] = 1; }
        else if (horizontal) {
            double firstWidth = DY778LayoutMin(recall.width, (frame.width - 4) * .5);
            result.frames[1] = (DY778LayoutRect){frame.x, frame.y, firstWidth, frame.height};
            result.frames[2] = (DY778LayoutRect){frame.x + firstWidth + 4, frame.y, frame.width - firstWidth - 4, frame.height};
            result.visible[1] = result.visible[2] = 1;
        } else {
            result.frames[1] = (DY778LayoutRect){frame.x, frame.y, frame.width, recall.height};
            result.frames[2] = (DY778LayoutRect){frame.x, frame.y + recall.height + 2, frame.width, edit.height};
            result.visible[1] = result.visible[2] = 1;
        }
    }
    return result;
}
#endif
