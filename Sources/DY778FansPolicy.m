#include "DY778FansPolicy.h"
#include <string.h>
#include <math.h>

bool DY778FansParseUnsigned(const char *text, size_t length, uint64_t maximum, uint64_t *value) {
    if (!text || !length || length > 20) return false;
    uint64_t result = 0;
    for (size_t i = 0; i < length; i++) {
        unsigned char digit = (unsigned char)text[i];
        if (digit < '0' || digit > '9') return false;
        uint64_t part = digit - '0';
        if (part > maximum || result > (maximum - part) / 10) return false;
        result = result * 10 + part;
    }
    if (value) *value = result;
    return true;
}
bool DY778FansASCIIUID(const char *text, size_t length) {
    uint64_t value = 0;
    return DY778FansParseUnsigned(text, length, UINT64_MAX, &value) && value > 0;
}
bool DY778FansASCIIHandle(const char *text, size_t length) {
    if (!text || !length || length > 64) return false;
    for (size_t i = 0; i < length; i++) {
        unsigned char c = (unsigned char)text[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '-')) return false;
    }
    return true;
}
bool DY778FansASCIISECUid(const char *text, size_t length) {
    if (!text || length < 20 || length > 256 || memcmp(text, "MS4wLjAB", 8)) return false;
    for (size_t i = 8; i < length; i++) {
        unsigned char c = (unsigned char)text[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '=')) return false;
    }
    return true;
}
int DY778FansProfileButtonWidth(double freeWidth) {
    if (!isfinite(freeWidth) || freeWidth < 44) return 0;
    return freeWidth >= 82 ? 82 : 44;
}
bool DY778FansCallbackCurrent(uint64_t expectedGeneration, uint64_t generation, uint64_t expectedOperation, uint64_t operation, bool pending) {
    return pending && expectedGeneration == generation && expectedOperation == operation;
}
