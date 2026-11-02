#ifndef DY778ArchivePolicy_h
#define DY778ArchivePolicy_h
#include <stdbool.h>
#include <string.h>

static inline bool DY778ArchiveIDPresent(const char *value) {
    return value && value[0] && strcmp(value, "0") != 0;
}
static inline bool DY778ArchiveSameID(const char *left, const char *right) {
    return DY778ArchiveIDPresent(left) && DY778ArchiveIDPresent(right) && strcmp(left, right) == 0;
}
static inline bool DY778ArchiveMediaSelectable(const char *messageKind, const char *candidateKind,
    bool directMessage, bool cover, bool shared) {
    if (!directMessage) return true;
    return DY778ArchiveSameID(messageKind, candidateKind) && !cover && !shared;
}
static inline bool DY778ArchiveIdentityMatches(const char *account, const char *currentAccount,
    const char *conversation, const char *actualConversation, const char *client, const char *actualClient,
    const char *server, const char *actualServer) {
    if (!DY778ArchiveSameID(account, currentAccount) || !DY778ArchiveSameID(conversation, actualConversation)) return false;
    if (DY778ArchiveIDPresent(server) && DY778ArchiveIDPresent(actualServer) && !DY778ArchiveSameID(server, actualServer)) return false;
    return DY778ArchiveSameID(client, actualClient) || DY778ArchiveSameID(server, actualServer);
}
#endif
