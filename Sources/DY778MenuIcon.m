#import "DY778Core.h"
#import <math.h>

UIImage *DY778MenuIcon(NSString *symbol) {
    if (![symbol isKindOfClass:NSString.class] || !symbol.length) return nil;
    static NSCache<NSString *, UIImage *> *images;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ images = [NSCache new]; images.countLimit = 128; });
    CGFloat scale = UIScreen.mainScreen.scale;
    if (!isfinite(scale) || scale <= 0) scale = 2;
    NSString *key = [NSString stringWithFormat:@"%@|%g", symbol, (double)scale];
    UIImage *cached = [images objectForKey:key];
    if (cached) return cached;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightMedium];
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:configuration] ?:
        [UIImage systemImageNamed:@"circle" withConfiguration:configuration];
    if (!image || image.size.width <= 0 || image.size.height <= 0) return nil;
    image = [image imageWithTintColor:UIColor.blackColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    CGFloat fit = MIN(1, 24 / MAX(image.size.width, image.size.height));
    CGSize size = CGSizeMake(image.size.width * fit, image.size.height * fit);
    CGRect bounds = CGRectMake(round((28 - size.width) * .5 * scale) / scale,
                               round((28 - size.height) * .5 * scale) / scale,
                               size.width, size.height);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO; format.scale = scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(28, 28) format:format];
    UIImage *result = [[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [image drawInRect:bounds];
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [images setObject:result forKey:key];
    return result;
}
