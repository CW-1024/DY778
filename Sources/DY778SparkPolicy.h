#ifndef DY778_SPARK_POLICY_H
#define DY778_SPARK_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

static inline bool DY778SparkSingleChatParts(const char *identifier, const char **first, size_t *firstLength,
                                            const char **second, size_t *secondLength) {
    if (!identifier || !*identifier) return false;
    const char *parts[4] = {identifier, NULL, NULL, NULL};
    size_t lengths[4] = {0, 0, 0, 0}, section = 0, total = 0;
    for (const char *p = identifier; *p; p++) {
        if (++total > 512) return false;
        if (*p == ':') {
            if (!lengths[section] || section == 3 || (section == 0 && lengths[0] == 1 && *identifier == '-')) return false;
            parts[++section] = p + 1;
        } else {
            if ((*p < '0' || *p > '9') && !(section == 0 && lengths[0] == 0 && *p == '-')) return false;
            lengths[section]++;
        }
    }
    if (section != 3 || !lengths[3] || lengths[1] != 1 || *parts[1] != '1' ||
        lengths[2] > 32 || lengths[3] > 32 || *parts[2] == '0' || *parts[3] == '0' ||
        (lengths[2] == lengths[3] && !memcmp(parts[2], parts[3], lengths[2]))) return false;
    if (first) *first = parts[2];
    if (firstLength) *firstLength = lengths[2];
    if (second) *second = parts[3];
    if (secondLength) *secondLength = lengths[3];
    return true;
}
static inline bool DY778SparkSingleChatPeer(const char *identifier, const char *account, char *peer, size_t capacity) {
    const char *first, *second; size_t firstLength, secondLength;
    if (!account || !*account || !peer || !capacity ||
        !DY778SparkSingleChatParts(identifier, &first, &firstLength, &second, &secondLength)) return false;
    size_t length = strlen(account), peerLength = 0;
    const char *source = NULL;
    if (length == firstLength && !memcmp(account, first, length)) { source = second; peerLength = secondLength; }
    else if (length == secondLength && !memcmp(account, second, length)) { source = first; peerLength = firstLength; }
    if (!source || peerLength >= capacity) return false;
    memcpy(peer, source, peerLength); peer[peerLength] = '\0'; return true;
}
static inline bool DY778SparkSingleChatBindingMatches(const char *identifier, const char *account,
                                                      const char *knownOwner, const char *knownPeer) {
    char peer[33];
    if (!DY778SparkSingleChatPeer(identifier, account, peer, sizeof(peer))) return false;
    return (!knownOwner || !*knownOwner || !strcmp(knownOwner, account)) &&
           (!knownPeer || !*knownPeer || !strcmp(knownPeer, peer));
}

static inline bool DY778SparkGroupBindingMatches(const char *identifier, const char *account,
                                                 const char *sdkOwner, unsigned nativeType,
                                                 bool currentUserIsParticipant) {
    if (!identifier || !*identifier || !account || !*account || !sdkOwner || !*sdkOwner ||
        nativeType != 2 || !currentUserIsParticipant || strcmp(account, sdkOwner)) return false;
    size_t length = 0;
    for (const unsigned char *p = (const unsigned char *)identifier; *p; p++) {
        if (++length > 512 || *p <= 32 || *p >= 127) return false;
    }
    return !DY778SparkSingleChatParts(identifier, NULL, NULL, NULL, NULL);
}

static inline bool DY778SparkParseDays(const char *text, unsigned *result) {
    if (!text || !*text || !result) return false;
    unsigned value = 0, length = 0;
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        if (++length > 5 || *p < '0' || *p > '9' || value > 9999) return false;
        value = value * 10 + (*p - '0');
    }
    if (value < 1 || value > 99999) return false;
    *result = value;
    return true;
}
static inline bool DY778SparkScopeMatches(const char *account, const char *conversation,
                                          const char *currentAccount, const char *currentConversation) {
    return account && *account && conversation && *conversation && currentAccount && currentConversation &&
           !strcmp(account, currentAccount) && !strcmp(conversation, currentConversation);
}
static inline bool DY778SparkNativeAppearanceMatches(long long nativeState, bool lit) {
    return lit ? nativeState == 1 : nativeState == 2 || nativeState == 3;
}
static inline unsigned DY778SparkDetailDisplayState(bool lit) { return lit ? 0u : 1u; }
static inline unsigned DY778SparkNativeDisplayState(bool lit) { return lit ? 1u : 2u; }
static inline bool DY778SparkDeliveryIsCurrent(unsigned long long capturedGeneration, unsigned long long currentGeneration,
                                               unsigned long long capturedRevision, unsigned long long currentRevision,
                                               bool sameScope) {
    return sameScope && capturedGeneration == currentGeneration && capturedRevision == currentRevision;
}
static inline bool DY778SparkRouteFieldCompatible(const char *existing, const char *incoming) {
    return !existing || !*existing || !incoming || !*incoming || !strcmp(existing, incoming);
}
static inline bool DY778SparkNeedsNormalAppearance(long long nativeState, bool guideStyle) {
    return guideStyle || (nativeState != 1 && nativeState != 2 && nativeState != 3);
}
static inline bool DY778SparkPopupRouteMatches(const char *boundAccount, const char *boundConversation,
                                              const char *currentAccount, const char *routeConversation,
                                              const char *boundChannel, const char *boundBundle,
                                              const char *routeChannel, const char *routeBundle) {
    return DY778SparkScopeMatches(boundAccount, boundConversation, currentAccount, routeConversation) &&
           boundChannel && *boundChannel && boundBundle && *boundBundle && routeChannel && routeBundle &&
           !strcmp(boundChannel, routeChannel) && !strcmp(boundBundle, routeBundle);
}
#endif
