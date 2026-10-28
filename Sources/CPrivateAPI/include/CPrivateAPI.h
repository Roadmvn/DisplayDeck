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

// La luminosité change aussi en dehors de l'app (touches du clavier, capteur de lumière) :
// sans ces notifications, un curseur affiche une valeur périmée dès la première pression sur F1.
typedef void (*DDBrightnessObserver)(CGDirectDisplayID display, float value, void *_Nullable context);
bool DDObserveBrightness(CGDirectDisplayID display, void *_Nullable context, DDBrightnessObserver observer);
void DDStopObservingBrightness(CGDirectDisplayID display);
// `deinit` ne peut pas lire l'état isolé du main actor : le désabonnement global s'en passe.
void DDStopObservingAllBrightness(void);

// Luminosité automatique : l'écran suit le capteur de lumière ambiante.
bool DDHasAmbientLightCompensation(CGDirectDisplayID display);
bool DDAmbientLightCompensationEnabled(CGDirectDisplayID display);
void DDSetAmbientLightCompensation(CGDirectDisplayID display, bool enabled);

// Bandeau système (OSD.framework, chargé à l'exécution) : le même que celui des touches de luminosité.
typedef enum {
    DDOSDImageContrast = 0,
    DDOSDImageBrightness = 1,
    DDOSDImageVolume = 3,
    DDOSDImageVolumeMuted = 4,
} DDOSDImage;

// `filled` sur `total` cases remplies ; macOS en dessine 16 pour ses propres bandeaux.
void DDShowOSD(DDOSDImage image, CGDirectDisplayID display, uint32_t filled, uint32_t total);

// DDC/CI des écrans externes via IOAVService (Apple Silicon). Appels bloquants : jamais sur le main thread.
NSArray *DDExternalAVServices(void);
bool DDReadEDIDIdentity(CFTypeRef service, uint32_t *vendor, uint32_t *product, uint32_t *serial);
void DDWriteVCP(CFTypeRef service, uint8_t code, uint16_t value);
bool DDReadVCP(CFTypeRef service, uint8_t code, uint16_t *current, uint16_t *maximum);

NS_ASSUME_NONNULL_END
