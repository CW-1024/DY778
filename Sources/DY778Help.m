#import "DY778Help.h"
#import <QuartzCore/QuartzCore.h>

@interface DY778HelpController : UITableViewController
@property(nonatomic, strong) NSArray<NSDictionary *> *topics;
@end
@implementation DY778HelpController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"使用说明";
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 210;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    self.tableView.showsVerticalScrollIndicator = YES;
    self.topics = @[
        @{@"title": @"主页与作品数字", @"icon": @"number.circle", @"body": @"开启“启用数字自定义”后，已填写的主页与本人作品数字直接生效。长按本人主页的获赞、互关、关注或粉丝数字及其下方文字，可单独编辑该项；普通点击保持原来的用法，官方获赞弹窗与有计数的本人关系页标题同步显示设置值。\n\n本人作品统一从设置页的“按作品单独设置”编辑，支持点赞、评论、收藏、分享和播放数。列表收录本次已浏览的本人作品及已有配置，不同账号和作品分别保存。单作品数值优先于通用值，单项留空表示跟随通用设置。\n\n启用时，手动下拉刷新“我”页会清除当前账号的全部数字设置，包括主页四项，以及作品的点赞、评论、收藏、分享和播放量。通用与单作品配置一起清除，总开关保持开启，可继续重新设置。恢复时会显示提示，进入页面、切换标签或自动刷新不会触发恢复。\n\n关闭总开关会恢复原值并保留配置。单作品的“此作品使用原始数字”可绕过全部覆盖；“清除并恢复原始数字”清除该作品数值并使用原值，“跟随通用设置”回到通用规则。“恢复当前账号原状”清除该账号全部数字设置，总开关保持原状态。\n\n支持 0–999999999 的整数，仅改变本机显示，不修改真实互动或其他人的显示。沿用抖音已有的计数位置和样式，不新增原界面没有的数字标签。"},
        @{@"title": @"聊天火花", @"icon": @"flame", @"body": @"在“消息 → 聊天火花”开启总开关，再进入单聊或群聊右上角信息页，选择“自定义火花”。可为该聊天单独开启，设置点亮或熄灭，以及 1–99999 天。支持原生入口的已点亮、已熄灭和“点亮中”状态，沿用抖音原生图标与布局。仅改变本机显示，不影响真实天数、奖励或对方看到的内容。\n\n设置按账号和会话分别保存。关闭开关恢复原值并保留设置；“恢复此聊天原状”清除当前会话配置。插件内的“恢复当前账号全部火花”和消息页右上角“＋ → 恢复火花显示”执行同一种恢复：清除当前账号全部会话的火花配置，保留总开关及其他账号设置。\n\n修改与恢复会同步更新聊天顶部、会话列表和已适配的原生详情。部分详情容器未能建立对应关系时，可关闭详情后重新进入。没有原生火花展示位置的聊天不会额外创建火花图标或详情入口。"},
        @{@"title": @"列表清理", @"icon": @"rectangle.stack.badge.minus", @"body": @"在“显示与整理 → 列表清理”开启“长按清空列表”，回到“我”页长按“推荐”“收藏”或“喜欢”标签，确认后处理对应作品列表，无需先切换标签。普通点击保持原来的用法。\n\n这会实际取消当前账号的推荐、作品收藏或喜欢，不会删除作品，无法一键撤销。收藏不涉及音乐、地点等其他分类；失效、不可见或无法读取的作品可能需要手动处理。\n\n确认后停留在当前主页，顶部提示读取和清理进度，点击提示中的“停止”可结束后续处理。先完整读取列表，再分批取消，仅统计已核对的结果；完成时显示勾选动画与触感反馈。\n\n关闭开关、离开本人主页、切换账号、退到后台或结果异常时停止后续处理。已提交的请求可能继续完成，已成功的取消会保留，请刷新原列表核对。遇到平台频率限制可稍后再试，不会自动反复重试。"},
        @{@"title": @"推荐页直播信息", @"icon": @"person.2.wave.2", @"body": @"在“直播信息”中分别开启在线人数和卡片开播时长。两项使用独立胶囊，卡片停稳后显示；同时开启时上下排列并留出间距，单开时只显示对应项。胶囊仅显示图标和数值，在线人数支持简洁或完整格式；简洁格式保留“万”“亿”单位，刷新间隔为 2–10 秒。\n\n缺少可靠数据时暂不显示对应项，不会以零值代替。切换卡片、进入直播间或退到后台后停止原卡片的更新；展示数据可能存在延迟，以抖音实际返回为准。"},
        @{@"title": @"直播间开播时长", @"icon": @"clock", @"body": @"在“直播信息 → 直播间浮层”开启。胶囊默认居中靠上，可拖动到合适位置，横屏和竖屏分别记忆。文字大小、文字颜色、背景颜色和不透明度均可调整，点击“恢复默认位置”可重置两种方向的位置。\n\n未取得开播时间时暂不显示。切房、离开直播或退到后台后停止更新；返回后读取当前直播间。推荐页卡片时长单独控制，保持统一胶囊样式。"},
        @{@"title": @"特别关注", @"icon": @"person.crop.circle.badge.checkmark", @"body": @"开启总开关后添加关注对象，最多 20 人。可从互关好友选择，也可输入抖音号核对后添加。聊天右上角的信息页可对单个人开启或暂停，暂停会保留已有档案。\n\n仅在抖音前台检测，默认间隔 300 秒，可设为 30–300 秒。多人依次排队，异常时自动减慢，后台期间不检测或补发请求。首次成功读取仅建立基线，之后记录可读取的获赞、关注、粉丝、喜欢数量、简介及喜欢作品变化。\n\n数据受当前账号可见权限与平台返回影响。发现时间不等于实际操作时间，数量变化无法确认具体关系；不会补全私密或未取得的信息。账号切换后使用各自档案。默认保留 7 天、500 条，可调整或清理，关闭动态提醒仍会记录变化。"},
        @{@"title": @"星牌查询", @"icon": @"star.circle", @"body": @"开启后，用户主页顶部会出现“星牌”按钮。点按读取该用户可查询的消费等级和粉丝灯牌；选择主播可进一步核对对应灯牌。按钮会按主页可用空间调整，空间不足时暂不显示。\n\n未返回资料不代表没有加入，等级区间不代表实际消费金额。查询结果不保存为本地历史，可复制本次结果。退到后台、退出查询、切换账号或关闭功能后停止当前任务，返回后可重新查询。"},
        @{@"title": @"操作确认", @"icon": @"checkmark.shield", @"body": @"分别开启作品点赞、收藏、关注、评论点赞和评论点踩确认。弹窗会区分执行操作和取消已有操作；点击“暂不操作”或弹窗外区域取消，确认后才继续。\n\n确认前会复查内容与状态，切换内容、账号或退到后台后不会执行旧操作。评论状态暂无法读取时会提示重试。不同抖音版本与页面的入口可能存在差异。"},
        @{@"title": @"直播自动点赞", @"icon": @"hand.thumbsup", @"body": @"在“直播自动点赞”中开启功能，设置每轮 1–9999 次，默认 100 次。点赞间隔支持 0.6–2 秒，默认 1 秒；每 20 次的休息时间支持 1–3 秒，默认 1.5 秒，两项均以 0.1 秒调整。返回直播画面双击开始；每完成 20 次自动点赞，将下一次间隔调整为休息时间，且不短于普通点赞间隔，之后恢复正常节奏。休息时间不额外叠加，等待提交反馈时可能更久。\n\n再次双击、离开或切换直播间、切到后台、修改次数或节奏、关闭开关都会结束本轮，不会在返回时自动续跑。提交失败或长时间没有反馈时也会停止，可稍后重新开始。\n\n顶部仅显示“自动点赞中 已执行次数/目标次数”，不包含触发时的手动双击；达到目标后等待本轮提交结果，确认完成后提示自动收起。直播间总数包含其他观众，并受刷新节奏及平台计数规则影响，实际增量以直播间显示为准。\n\n间隔和休息时间越短、连续使用越频繁，越容易触发抖音的频率限制或风控，可能出现延迟、少计或暂停。建议优先使用默认节奏，按需设置次数；如遇异常，可延长间隔或休息时间、稍后再试。次数上限与短暂停顿用于控制连续操作，不代表免受风控。"},
        @{@"title": @"视频默认倍速", @"icon": @"speedometer", @"body": @"在视频播放中开启“视频作品默认倍速”，可选 1.25×、2×、2.5×、3×，或输入 1–3 之间、最多两位小数的自定义值。此开关首次关闭，直播和图文不调整。\n\n长按加速期间优先使用长按速度。修改默认倍速后即时更新可用的视频播放器；关闭时只恢复本插件接管的速度。"},
        @{@"title": @"测试 · 跳过疑似广告", @"icon": @"line.3.horizontal.decrease.circle", @"body": @"此功能首次关闭，仅在首页推荐流尝试跳过，视频和图文均适用。已关注、已点赞、已收藏及自己的作品优先保留。其余作品根据抖音广告标记、推广信息和促销文案判断。\n\n疑似推广需同时有明确价格、购买引导和优惠细节。结合商品链接、套餐、赠品和限时优惠等信息判断。品牌名、普通价格、双11话题本身不足以触发。没有明确广告证据时，测评、探店、避雷、新闻和教程等语境会保留。\n\n作品停稳后短暂复查晚加载的广告标签；滚动、操作面板或离开推荐页时不跳过。使用抖音原生切换，不删除作品，下滑可回看，已跳过的近期作品不会再次跳过；连续自动跳过最多三条。\n\n判断依据是作品描述、商品信息和广告标记，不识别视频或图片画面里的文字。隐晦推广仍可能漏判，实验规则也可能误判，可随时关闭。"},
        @{@"title": @"从这里开始", @"icon": @"sparkles", @"body": @"首次安装时各项增强功能默认关闭，到对应页面开启需要的功能即可。入口位于抖音设置页，名称为 DY778。\n\n同一应用内升级 DY778 时沿用已有设置和记录；恢复默认设置会关闭增强功能，并保留已保存的消息记录。"},
        @{@"title": @"防撤回 · 按会话控制", @"icon": @"bubble.left.and.bubble.right", @"body": @"开启消息防撤回后，全部会话默认生效。进入某个聊天，点右上角 ··· → 本会话防撤回，可单独关闭或重新打开，立即生效。关闭总开关会暂停全部会话。\n\n已撤回消息可以显示小标记，默认“已撤回”，可改成最多 12 个字符的文字或表情；留空恢复默认。默认保留对方原有的聊天气泡皮肤。可独立开启“撤回后使用普通气泡”，将文字消息的皮肤背景与动画替换为普通气泡；自定义撤回颜色已开启时优先使用所选颜色，否则采用聊天主题的普通底色并匹配文字对比度。关闭开关会保留原皮肤。表情包、图片和视频画面不会被改色或替换，自己的撤回操作保持正常。"},
        @{@"title": @"撤回提醒与后台运行", @"icon": @"bell.badge", @"body": @"撤回提醒是独立开关，首次默认关闭，只提醒已启用防撤回的会话。前台显示可点开的消息卡片；后台实际收到撤回事件时，可发送系统通知。默认不展示消息摘要，可单独打开。\n\n后台保存使用系统允许的短时任务。抖音被系统挂起或关闭后，插件不能独立接收新消息，也不能无限延长后台运行。再次进入时，会在消息重新加载后核对之前保存的内容。未收到、未缓存的消息无法凭通知还原。"},
        @{@"title": @"时间与标记 · 紧贴消息", @"icon": @"clock", @"body": @"时间、撤回标记和编辑标记可分别选择上方、下方或右侧。右侧位置跟随实际气泡、视频分享卡片的边缘。多个标记都放右侧时，上下排列，避免相互覆盖。\n\n消息较宽、长日期或屏幕空间不足时，会自动避让到可用位置。预览显示当前账号头像，加载完成前显示 🤡。"},
        @{@"title": @"查看撤回记录", @"icon": @"tray.full", @"body": @"消息留存 → 已撤回的消息，按联系人或群查看内容和时间。分享作品可打开原作品；图片、语音和视频优先使用抖音现有的本地媒体。没有可预览的媒体时，点按“在聊天中查看”定位原消息并短暂高亮整行。滑动聊天或离开会话会结束高亮；原消息已从本机移除时会提示无法定位。\n\n分享作品附带的评论在同一条记录中显示首次取得的文字和作者，后续删除提示不会覆盖已保存文字。系统撤回提示和空白卡片不单独列入记录。\n\n默认保存天数和数量均为 0，不自动过期。消息记录可以按单条、会话或当前账号删除；主动设置保留限制或移除应用数据也会清理记录。只能保存本机当时收到的内容；语音评论仅留存已取得的转写文字，媒体原件不作永久保存。"},
        @{@"title": @"编辑历史", @"icon": @"pencil.circle", @"body": @"编辑历史与防撤回独立开启。启用后留存对方消息原文和本机收到的编辑版本，支持按会话开关。点击消息旁的“编辑历史”可直达该条消息，聊天信息页和插件设置页也有入口。标记文字支持最多 12 个字符或表情，留空恢复默认；上方、下方或右侧位置独立设置，后方显示已留存编辑次数。\n\n编辑气泡染色默认关闭，关闭时保持原本颜色。开启后仅调整可着色背景，透明媒体保持原样；消息同时已撤回时，已开启的撤回底色优先。设置页提供实时预览。\n\n编辑提醒和提醒摘要分别默认关闭。开启提醒后，已留存消息的新版本成功保存才提醒，首次加载就已编辑的旧消息与重复事件不提醒。前台显示可点开的卡片，后台实际收到事件时发送本地通知，点按打开该条消息的编辑历史。系统权限与运行限制同撤回提醒。\n\n历史按会话和消息分组，显示原消息发送时间、首次留存时间、每次编辑时间以及本机接收时间。没有服务端时间时明确显示发现时间；首次收到就已编辑的消息会提示原文未取得。离线或应用被挂起期间的中间版本无法补回。"},
        @{@"title": @"福袋 · 先看条件再参与", @"icon": @"gift", @"body": @"首次开启时会说明参与范围，阅读两秒后可确认。助手只处理当前直播间的普通免费福袋，自动完成所需评论与报名。确认模式先显示主播、奖品、倒计时和条件，点击“一键参与”后执行；自动模式静默完成这些操作，确认成功后才显示“本场福袋已参与”。\n\n需要本主播灯牌或最低等级时，先向平台核对：已持有有效灯牌且等级足够，可以继续评论并报名；未达标、状态不明，或存在送礼、付费及其他额外条件时跳过。助手不会代为点亮、升级、关注或消费。条件中的灯牌要求会单独着色，已满足为绿色，待核对或未满足为橙色。\n\n每场评论只发送一次，不覆盖正在编辑的草稿。报名按钮没有响应时会短暂等待并补试，单次任务最多三次。仅平台参与状态确认后才算成功；没有确认的结果可在“最近参与记录”中查看。\n\n自动模式不弹出报名页面。切房、退后台、暂停、关闭助手或自行打开官方福袋时会停止当前自动任务。小型悬浮入口可选开启、拖动或收起；关闭总开关后不再显示助手弹窗与悬浮入口。"},
        @{@"title": @"福袋状态怎么读", @"icon": @"checkmark.circle", @"body": @"发现福袋：已取得本场信息。\n正在核对条件：正在确认本主播的灯牌与等级。\n本场不自动参与：条件未达标、无法确认或超出助手处理范围。\n口令已提交：已提交本场所需口令。\n参与操作已提交：已经执行报名操作，仍在等待平台确认。\n已参与：取得抖音的参与确认。\n\n灯牌未点亮或等级不足时，顶部提示“灯牌条件未满足，已跳过本场福袋”。查询失败或信息不完整时，提示“暂未确认参与资格，已跳过本场福袋”。同一账号、同一场福袋只提示一次；之后确认灯牌达标，仍可继续参与。\n\n退出直播后，“最近参与记录”保留已发生的操作与结果，只供查看，不会继续执行旧房间的任务。助手不改变开奖概率。"},
        @{@"title": @"播放与长按倍速", @"icon": @"play.rectangle", @"body": @"看完视频作品自动暂停：到结尾后使用抖音原生暂停状态与图标，可点按继续播放或切到下一条。\n\n自定义长按倍速：默认 2×，可选常用速度或输入 1×–3×，最多两位小数，例如 1.25×、2.50×。使用抖音原有的长按加速手势，直播与没有原生加速入口的页面不强行改变速度。"},
        @{@"title": @"缓存用量与清理", @"icon": @"internaldrive", @"body": @"缓存管理显示应用缓存、临时文件、页面资源、投屏缓存和日志的总用量，自动换算 MB / GB。下拉或点击右上角可重新统计。\n\n清理全部缓存：清空上述目录中的普通缓存文件，仅保留识别到的插件配置。普通缓存数据库、JSON、资源包、无扩展名文件和新产生的缓存均会清理。可以中途停止，手动操作无需开启自动整理。\n\n清理会保留可识别的插件配置，应用设置、普通文档和 DY778 消息档案不在清理范围。\n\n启动抖音时清理与从后台返回时清理是两个独立开关，首次均关闭。每次触发都会清空缓存，不依赖容量或时间规则。短暂打开控制中心或权限弹窗不算后台返回。顶部会显示清理进度与本次清理量。\n\n按规则自动清理是第三个独立开关。容量超限时先清理最旧文件；时间支持 1 天、1 周、1 个月、自定义小时或从不。选择“从不”只关闭时间限制，容量超限仍会清理；两项都为 0 时不执行按规则清理。\n\n完成后重新统计实际剩余用量，不会强行显示为零。继续使用抖音会产生新缓存，保留在缓存目录中的插件配置也会计入目录总用量。此处不是系统设置中的抖音全部占用。"},
        @{@"title": @"显示与共存", @"icon": @"paintpalette", @"body": @"背景默认跟随抖音，可单独选择深浅色。字号、颜色、时间格式与标签位置都可以调整。\n\n如果同一条消息出现两套时间或撤回提示，先关闭其他插件的同类功能。DY778 保留其他插件添加的文字和控件。"}
    ];
    DY778StyleController(self);
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; DY778StyleController(self); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.topics.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *topic = self.topics[path.section];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = DY778CardBackground(); cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIImageView *icon = [[UIImageView alloc] initWithImage:DY778MenuIcon(topic[@"icon"])];
    icon.tintColor = DY778Accent(); icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.widthAnchor constraintEqualToConstant:25].active = YES;
    UILabel *title = [UILabel new]; title.text = topic[@"title"]; title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.numberOfLines = 0; title.adjustsFontForContentSizeCategory = YES; title.textColor = UIColor.labelColor;
    UIStackView *heading = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title]]; heading.spacing = 10;
    UILabel *body = [UILabel new]; body.numberOfLines = 0; body.adjustsFontForContentSizeCategory = YES;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new]; paragraph.lineSpacing = 5; paragraph.paragraphSpacing = 5;
    body.attributedText = [[NSAttributedString alloc] initWithString:topic[@"body"] attributes:@{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody],
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor, NSParagraphStyleAttributeName: paragraph}];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[heading, body]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-22]
    ]];
    return cell;
}
@end
void DY778PresentHelp(UIViewController *source) { DY778PresentController(source, [DY778HelpController new]); }
