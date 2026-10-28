#import "CPrivateAPI.h"

#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <unistd.h>

#pragma mark - DisplayServices

static struct {
    bool (*canChange)(CGDirectDisplayID);
    int (*get)(CGDirectDisplayID, float *);
    int (*set)(CGDirectDisplayID, float);
    int (*observe)(CGDirectDisplayID, void *, CFNotificationCallback);
    int (*stopObserving)(CGDirectDisplayID, void *);
    bool (*hasAmbient)(CGDirectDisplayID);
    // Celle-ci rend un code de retour et écrit dans un paramètre de sortie, contrairement à `hasAmbient`.
    int (*ambientEnabled)(CGDirectDisplayID, bool *);
    int (*setAmbient)(CGDirectDisplayID, bool);
} DisplayServices;

static void LoadDisplayServices(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
        if (handle == NULL) return;
        DisplayServices.canChange = dlsym(handle, "DisplayServicesCanChangeBrightness");
        DisplayServices.get = dlsym(handle, "DisplayServicesGetBrightness");
        DisplayServices.set = dlsym(handle, "DisplayServicesSetBrightness");
        DisplayServices.observe = dlsym(handle, "DisplayServicesRegisterForBrightnessChangeNotifications");
        DisplayServices.stopObserving = dlsym(handle, "DisplayServicesUnregisterForBrightnessChangeNotifications");
        DisplayServices.hasAmbient = dlsym(handle, "DisplayServicesHasAmbientLightCompensation");
        DisplayServices.ambientEnabled = dlsym(handle, "DisplayServicesAmbientLightCompensationEnabled");
        DisplayServices.setAmbient = dlsym(handle, "DisplayServicesEnableAmbientLightCompensation");
    });
}

bool DDCanChangeBrightness(CGDirectDisplayID display) {
    LoadDisplayServices();
    return DisplayServices.canChange != NULL && DisplayServices.get != NULL && DisplayServices.set != NULL
        && DisplayServices.canChange(display);
}

bool DDGetBrightness(CGDirectDisplayID display, float *value) {
    LoadDisplayServices();
    return DisplayServices.get != NULL && DisplayServices.get(display, value) == 0;
}

void DDSetBrightness(CGDirectDisplayID display, float value) {
    LoadDisplayServices();
    if (DisplayServices.set != NULL) DisplayServices.set(display, value);
}

#pragma mark - Notifications de luminosité

// DisplayServices rend la valeur à un rappel CFNotificationCenter et ne repasse que le pointeur
// d'observateur : on y place la structure d'inscription pour retrouver l'écran et le destinataire.
typedef struct {
    CGDirectDisplayID display;
    DDBrightnessObserver observer;
    void *context;
} DDBrightnessRegistration;

static NSMutableDictionary<NSNumber *, NSValue *> *BrightnessRegistrations(void) {
    static NSMutableDictionary *registrations;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ registrations = [NSMutableDictionary dictionary]; });
    return registrations;
}

static void BrightnessChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name,
                              const void *object, CFDictionaryRef userInfo) {
    DDBrightnessRegistration *registration = observer;
    if (registration == NULL || registration->observer == NULL) return;
    NSNumber *value = ((__bridge NSDictionary *)userInfo)[@"value"];
    if (value == nil) return;
    registration->observer(registration->display, value.floatValue, registration->context);
}

bool DDObserveBrightness(CGDirectDisplayID display, void *context, DDBrightnessObserver observer) {
    LoadDisplayServices();
    if (DisplayServices.observe == NULL) return false;
    // une seule inscription par écran : réinscrire sans arrêter l'ancienne fuirait sa structure
    DDStopObservingBrightness(display);

    DDBrightnessRegistration *registration = malloc(sizeof(DDBrightnessRegistration));
    if (registration == NULL) return false;
    *registration = (DDBrightnessRegistration){ .display = display, .observer = observer, .context = context };

    if (DisplayServices.observe(display, registration, BrightnessChanged) != 0) {
        free(registration);
        return false;
    }
    BrightnessRegistrations()[@(display)] = [NSValue valueWithPointer:registration];
    return true;
}

void DDStopObservingBrightness(CGDirectDisplayID display) {
    LoadDisplayServices();
    NSValue *stored = BrightnessRegistrations()[@(display)];
    if (stored == nil) return;
    [BrightnessRegistrations() removeObjectForKey:@(display)];
    DDBrightnessRegistration *registration = stored.pointerValue;
    if (DisplayServices.stopObserving != NULL) DisplayServices.stopObserving(display, registration);
    free(registration);
}

void DDStopObservingAllBrightness(void) {
    for (NSNumber *display in BrightnessRegistrations().allKeys) {
        DDStopObservingBrightness(display.unsignedIntValue);
    }
}

#pragma mark - Luminosité automatique

bool DDHasAmbientLightCompensation(CGDirectDisplayID display) {
    LoadDisplayServices();
    return DisplayServices.hasAmbient != NULL && DisplayServices.ambientEnabled != NULL
        && DisplayServices.setAmbient != NULL && DisplayServices.hasAmbient(display);
}

bool DDAmbientLightCompensationEnabled(CGDirectDisplayID display) {
    LoadDisplayServices();
    if (DisplayServices.ambientEnabled == NULL) return false;
    bool enabled = false;
    return DisplayServices.ambientEnabled(display, &enabled) == 0 && enabled;
}

void DDSetAmbientLightCompensation(CGDirectDisplayID display, bool enabled) {
    LoadDisplayServices();
    if (DisplayServices.setAmbient != NULL) DisplayServices.setAmbient(display, enabled);
}

#pragma mark - Bandeau système

// Classe privée d'OSD.framework, qui n'est pas lié : on passe par le nom à l'exécution.
@interface DDOSDManagerProxy : NSObject
- (void)showImage:(long long)image
      onDisplayID:(CGDirectDisplayID)display
         priority:(unsigned int)priority
    msecUntilFade:(unsigned int)msec
   filledChiclets:(unsigned int)filled
    totalChiclets:(unsigned int)total
           locked:(BOOL)locked;
@end

static DDOSDManagerProxy *_Nullable OSDManager(void) {
    static DDOSDManagerProxy *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (dlopen("/System/Library/PrivateFrameworks/OSD.framework/Versions/A/OSD", RTLD_LAZY) == NULL) return;
        Class class = NSClassFromString(@"OSDManager");
        if (![class respondsToSelector:@selector(sharedManager)]) return;
        manager = [class performSelector:@selector(sharedManager)];
    });
    return manager;
}

void DDShowOSD(DDOSDImage image, CGDirectDisplayID display, uint32_t filled, uint32_t total) {
    DDOSDManagerProxy *manager = OSDManager();
    SEL show = @selector(showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:);
    if (![manager respondsToSelector:show]) return;
    // 0x1f4 : la priorité qu'emploient les bandeaux de luminosité et de volume de macOS
    [manager showImage:image
          onDisplayID:display
             priority:0x1f4
        msecUntilFade:1000
       filledChiclets:filled
        totalChiclets:total
               locked:NO];
}

#pragma mark - IOAVService / DDC

typedef CFTypeRef IOAVServiceRef;
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);
extern IOReturn IOAVServiceCopyEDID(IOAVServiceRef service, CFDataRef *edid);

static const uint8_t DDCChipAddress = 0x37;
static const uint8_t DDCDataAddress = 0x51;
static const uint8_t DDCDisplayAddress = 0x6E;
static const uint8_t DDCReplyAddress = 0x50;

NSArray *DDExternalAVServices(void) {
    NSMutableArray *services = [NSMutableArray array];
    io_iterator_t iterator;
    if (IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, kIORegistryIterateRecursively, &iterator) != KERN_SUCCESS) {
        return services;
    }
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        if (IOObjectConformsTo(entry, "DCPAVServiceProxy")) {
            id location = CFBridgingRelease(IORegistryEntryCreateCFProperty(entry, CFSTR("Location"), kCFAllocatorDefault, 0));
            if ([location isEqual:@"External"]) {
                id service = CFBridgingRelease(IOAVServiceCreateWithService(kCFAllocatorDefault, entry));
                if (service != nil) [services addObject:service];
            }
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    return services;
}

bool DDReadEDIDIdentity(CFTypeRef service, uint32_t *vendor, uint32_t *product, uint32_t *serial) {
    CFDataRef raw = NULL;
    IOReturn status = IOAVServiceCopyEDID(service, &raw);
    NSData *edid = CFBridgingRelease(raw);
    if (status != kIOReturnSuccess || edid.length < 16) return false;
    const uint8_t *bytes = edid.bytes;
    *vendor = (uint32_t)bytes[8] << 8 | bytes[9];
    *product = (uint32_t)bytes[11] << 8 | bytes[10];
    // octets 12-15 de l'EDID, en petit-boutien : c'est ce que rend aussi CGDisplaySerialNumber
    *serial = (uint32_t)bytes[15] << 24 | (uint32_t)bytes[14] << 16 | (uint32_t)bytes[13] << 8 | bytes[12];
    return true;
}

static bool SendDDC(CFTypeRef service, uint8_t *packet, uint32_t length) {
    bool sent = false;
    // certains écrans ratent la première trame (contrôleur DDC lent à répondre) ; une commande VCP est idempotente, la doubler est sans risque
    for (int i = 0; i < 2; i++) {
        if (i > 0) usleep(10000);
        if (IOAVServiceWriteI2C(service, DDCChipAddress, DDCDataAddress, packet, length) == kIOReturnSuccess) sent = true;
    }
    return sent;
}

void DDWriteVCP(CFTypeRef service, uint8_t code, uint16_t value) {
    uint8_t hi = (uint8_t)(value >> 8);
    uint8_t lo = (uint8_t)(value & 0xFF);
    uint8_t packet[] = {0x84, 0x03, code, hi, lo, 0};
    packet[5] = DDCDisplayAddress ^ DDCDataAddress ^ 0x84 ^ 0x03 ^ code ^ hi ^ lo;
    SendDDC(service, packet, sizeof packet);
}

bool DDReadVCP(CFTypeRef service, uint8_t code, uint16_t *current, uint16_t *maximum) {
    uint8_t request[] = {0x82, 0x01, code, 0};
    request[3] = DDCDisplayAddress ^ DDCDataAddress ^ 0x82 ^ 0x01 ^ code;

    for (int attempt = 0; attempt < 4; attempt++) {
        if (attempt > 0) usleep(20000);
        if (!SendDDC(service, request, sizeof request)) continue;
        // la norme DDC/CI impose au moins 40 ms avant que l'écran ait préparé sa réponse
        usleep(50000);

        uint8_t reply[11] = {0};
        if (IOAVServiceReadI2C(service, DDCChipAddress, DDCDataAddress, reply, sizeof reply) != kIOReturnSuccess) continue;

        uint8_t checksum = DDCReplyAddress;
        for (int i = 0; i < 10; i++) checksum ^= reply[i];
        if (reply[2] != 0x02 || reply[3] != 0x00 || reply[4] != code || reply[10] != checksum) continue;

        *maximum = (uint16_t)(reply[6] << 8 | reply[7]);
        *current = (uint16_t)(reply[8] << 8 | reply[9]);
        return true;
    }
    return false;
}
