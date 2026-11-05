#ifndef DY778Fans_POLICY_H
#define DY778Fans_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

bool DY778FansParseUnsigned(const char *text, size_t length, uint64_t maximum, uint64_t *value);
bool DY778FansASCIIHandle(const char *text, size_t length);
bool DY778FansASCIIUID(const char *text, size_t length);
bool DY778FansASCIISECUid(const char *text, size_t length);
int DY778FansProfileButtonWidth(double freeWidth);
bool DY778FansCallbackCurrent(uint64_t expectedGeneration, uint64_t generation, uint64_t expectedOperation, uint64_t operation, bool pending);
#endif
