// 自动生成的私有常量，不含任何凭据。
#pragma once
typedef NS_ENUM(NSUInteger,DY778FansPrivateKey) {
    DY778FansLiveOrigin,
    DY778FansWebOrigin,
    DY778FansAppOrigin,
    DY778FansNativeOrigin,
    DY778FansCardPath,
    DY778FansMembersPath,
    DY778FansLiveUserPath,
    DY778FansLookupPath,
    DY778FansProfilePath,
    DY778FansSearchPath,
    DY778FansDiscoverPath,
    DY778FansNativeProfilePath,
    DY778FansVideoPath,
    DY778FansSignatureFunction,
    DY778FansSignedURLFormat,
};
static __attribute__((unused)) NSString *DY778FansPrivate(DY778FansPrivateKey key) {
    switch (key) {
        case DY778FansLiveOrigin: { static const volatile unsigned char raw[] = {9,244,235,206,174,198,52,21,53,17,225,211,251,144,124,71,40,25,225,128,174,131,102};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((97 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansWebOrigin: { static const volatile unsigned char raw[] = {0,243,210,181,151,57,13,110,23,8,233,147,184,148,111,64,49,25,184,214,187,158};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((104 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansAppOrigin: { static const volatile unsigned char raw[] = {7,250,217,188,152,48,6,103,6,241,192,169,134,44,82,46,44,13,249,215,245,153,118,85};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((111 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansNativeOrigin: { static const volatile unsigned char raw[] = {30,225,192,163,129,43,31,96,25,232,206,168,139,122,92,105,7,232,193,174,148,47,67,80,51};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((118 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansCardPath: { static const volatile unsigned char raw[] = {82,235,222,184,154,121,68,34,90,225,192,183,131,63,95,60,2,234,194,166,140,39};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((125 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansMembersPath: { static const volatile unsigned char raw[] = {171,212,167,131,99,126,77,41,83,253,219,183,139,116,90,32,22,188,209,189,133,109,113,56,31,238,216,150,132,110,85,49,75};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((132 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansLiveUserPath: { static const volatile unsigned char raw[] = {164,221,172,138,100,71,54,16,172,215,178,133,141,49};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((139 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansLookupPath: { static const volatile unsigned char raw[] = {189,198,181,141,33,76,60,2,165,223,250,200,115,86,33,17,173,200,174,185,145,50};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((146 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansProfilePath: { static const volatile unsigned char raw[] = {182,217,160,147,120,81,124,4,160,159,184,139,111,3,62,25,236,218,232,150,119,75,37,11,237,197,144,177,137,116,94,40,86};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((153 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansSearchPath: { static const volatile unsigned char raw[] = {143,222,169,152,113,94,117,15,169,152,161,144,118,28,53,20,254,202,188,140,96,4,57,12,233,213,165,141,43,80,43,15,231,243,219,242};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((160 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansDiscoverPath: { static const volatile unsigned char raw[] = {136,167,146,97,78,39,78,246,174,145,170,153,121,21,61,17,228,213,186,130,118,64,126,3,234,207,191,143,99,5};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((167 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansNativeProfilePath: { static const volatile unsigned char raw[] = {129,172,155,110,71,44,71,241,151,234,145,112,71,51,79,15,236,210,186,146,118,92,119,24,226,221,177,129,61};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((174 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansVideoPath: { static const volatile unsigned char raw[] = {154,181,132,119,92,53,64,248,156,227,138,125,76,37,2,169,193,161,151,99,72,44,112};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((181 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansSignatureFunction: { static const volatile unsigned char raw[] = {207,178,157,119,105,34,19,231,205};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((188 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
        case DY778FansSignedURLFormat: { static const volatile unsigned char raw[] = {230,162,36,96,0,123,61,186,218,133,155,119,80,35,6,169,150,146};
            unsigned char bytes[sizeof(raw)];
            for (NSUInteger i=0;i<sizeof(raw);i++) bytes[i] = raw[i] ^ ((195 + i * 31) & 255);
            return [[NSString alloc] initWithBytes:bytes length:sizeof(raw) encoding:NSUTF8StringEncoding]; }
    }
    return @"";
}
