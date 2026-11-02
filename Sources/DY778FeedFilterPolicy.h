#ifndef DY778_FEED_FILTER_POLICY_H
#define DY778_FEED_FILTER_POLICY_H
#include <stddef.h>
#include <string.h>
#include <ctype.h>

enum { DY778FeedKeep, DY778FeedOfficialAd, DY778FeedPromotion };
static inline unsigned DY778FeedTermCount(const char *text, const char *const *terms, size_t count) {
    unsigned found = 0;
    for (size_t i = 0; i < count; i++) if (strstr(text, terms[i])) found++;
    return found;
}
static inline int DY778FeedHasPrice(const char *text) {
    if (!text) return 0;
    for (const char *p = text; *p; p++) {
        if (!isdigit((unsigned char)*p) || (p != text && (isdigit((unsigned char)p[-1]) || p[-1] == '.'))) continue;
        const char *end = p;
        while (isdigit((unsigned char)*end)) end++;
        if (*end == '.' && isdigit((unsigned char)end[1])) {
            end++;
            while (isdigit((unsigned char)*end)) end++;
        }
        while (isspace((unsigned char)*end)) end++;
        const char *units[] = {"元", "块", "多吃", "多买", "多到手", "到手", "就能", "就吃",
            "一杯", "一份", "一套", "一件", "一盒", "一单", "一张", "一瓶", "一包", "一斤", "一餐", "一晚",
            "/杯", "/份", "/套", "/件", "/盒", "/单", "/张", "/瓶", "/包", "/斤", "/餐", "/晚"};
        for (size_t i = 0; i < sizeof(units)/sizeof(*units); i++)
            if (!strncmp(end, units[i], strlen(units[i]))) return 1;
        p = end-1;
    }
    const char *currency[] = {"¥", "￥"};
    for (size_t i = 0; i < 2; i++) {
        const char *p = text;
        while ((p = strstr(p, currency[i]))) {
            p += strlen(currency[i]);
            while (isspace((unsigned char)*p)) p++;
            if (isdigit((unsigned char)*p)) return 1;
        }
    }
    return 0;
}
static inline int DY778FeedPromotionReason(const char *text, int official, int commerce, int protectedPost) {
    if (protectedPost) return DY778FeedKeep;
    if (official) return DY778FeedOfficialAd;
    if (!text || strlen(text) > 12288) return DY778FeedKeep;
    const char *context[] = {"测评", "评测", "实测", "探店", "真实体验", "避雷", "踩雷", "吐槽", "不推荐", "别买", "不要买", "别囤",
        "骗局", "诈骗", "虚假", "维权", "投诉", "套路", "科普", "自制", "做法", "教程", "记录", "值不值", "能买吗", "不是广告", "非广", "无广",
        "刷到", "文案", "是不是", "真假", "真相", "有人说", "有人问", "朋友说", "朋友发", "网友说", "据说", "新闻", "曝光", "讨论", "解析", "模仿", "我买", "我吃", "我点", "我花", "自费", "听说", "求推荐", "求助", "好喝吗", "值得吗", "价格对比"};
    if (DY778FeedTermCount(text,context,sizeof(context)/sizeof(*context))) return DY778FeedKeep;
    const char *cta[] = {"赶紧囤", "赶快囤", "抓紧囤", "快去囤", "赶紧买", "赶快买", "抓紧买", "快去买",
        "赶紧抢", "赶快抢", "抓紧抢", "快去抢", "快来抢", "限时抢", "赶紧冲", "赶紧领", "快去领",
        "点击下方", "下方链接", "团购链接", "点左下角", "点击左下角", "橱窗下单", "小黄车下单", "现在下单", "马上下单", "领券下单"};
    const char *offer[] = {"到手", "仅需", "只要", "买一送一", "一共", "套餐", "五件套", "多件套", "任选", "可选", "重复选",
        "券后", "限时", "直降", "立省", "拍一发", "第二份", "第二件", "补贴", "活动价", "错过就没", "限量", "抢完", "售完", "恢复原价", "半价", "次卡", "券包"};
    unsigned calls = DY778FeedTermCount(text,cta,sizeof(cta)/sizeof(*cta));
    unsigned details = DY778FeedTermCount(text,offer,sizeof(offer)/sizeof(*offer));
    if (!calls || !details || !DY778FeedHasPrice(text)) return DY778FeedKeep;
    if (commerce) return DY778FeedPromotion;
    const char *bundle[] = {"买一送一", "五件套", "多件套", "重复选", "拍一发", "第二份", "第二件", "任选", "可选", "套餐", "次卡", "券包"};
    const char *scarcity[] = {"限时", "限量", "错过就没", "抢完", "售完", "恢复原价"};
    if (details >= 2 && (DY778FeedTermCount(text,bundle,sizeof(bundle)/sizeof(*bundle)) ||
        DY778FeedTermCount(text,scarcity,sizeof(scarcity)/sizeof(*scarcity)))) return DY778FeedPromotion;
    return DY778FeedKeep;
}
static inline int DY778FeedCanSkip(int enabled, int recommended, int visible, int interacting, int hasNext, int revisiting, unsigned recentSkips) {
    return enabled && recommended && visible && !interacting && hasNext && !revisiting && recentSkips < 3;
}
#endif
