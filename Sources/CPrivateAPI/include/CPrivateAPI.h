#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Classes privées de CoreGraphics. Un écran virtuel existe tant que son CGVirtualDisplay est retenu.
@class CGVirtualDisplay;

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) dispatch_queue_t queue;
@property(retain, nonatomic) NSString *name;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(copy, nonatomic, nullable) void (^terminationHandler)(id _Nullable, CGVirtualDisplay * _Nullable);
@end

@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) double refreshRate;
@property(readonly, nonatomic) unsigned int height;
@property(readonly, nonatomic) unsigned int width;
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property(nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) CGDirectDisplayID displayID;
- (nullable instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

// Luminosité matérielle de l'écran intégré (DisplayServices, chargé à l'exécution).
bool DDCanChangeBrightness(CGDirectDisplayID display);
bool DDGetBrightness(CGDirectDisplayID display, float *value);
void DDSetBrightness(CGDirectDisplayID display, float value);

// DDC/CI des écrans externes via IOAVService (Apple Silicon). Appels bloquants : jamais sur le main thread.
NSArray *DDExternalAVServices(void);
bool DDReadEDIDIdentity(CFTypeRef service, uint32_t *vendor, uint32_t *product);
void DDWriteVCP(CFTypeRef service, uint8_t code, uint16_t value);
bool DDReadVCP(CFTypeRef service, uint8_t code, uint16_t *current, uint16_t *maximum);

NS_ASSUME_NONNULL_END
