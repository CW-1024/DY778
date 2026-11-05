#ifndef DY778_SETTINGS_POLICY_H
#define DY778_SETTINGS_POLICY_H

static inline int DY778SettingsIsMainPage(int hasAccountSection, int isMainController, int isSearching) {
    return hasAccountSection || (isMainController && !isSearching);
}

#endif
