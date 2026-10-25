#import "CPrivateAPI.h"

#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <unistd.h>

#pragma mark - DisplayServices

static struct {
    bool (*canChange)(CGDirectDisplayID);
    int (*get)(CGDirectDisplayID, float *);
    int (*set)(CGDirectDisplayID, float);
} DisplayServices;

static void LoadDisplayServices(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
        if (handle == NULL) return;
        DisplayServices.canChange = dlsym(handle, "DisplayServicesCanChangeBrightness");
        DisplayServices.get = dlsym(handle, "DisplayServicesGetBrightness");
        DisplayServices.set = dlsym(handle, "DisplayServicesSetBrightness");
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

bool DDReadEDIDIdentity(CFTypeRef service, uint32_t *vendor, uint32_t *product) {
    CFDataRef raw = NULL;
    IOReturn status = IOAVServiceCopyEDID(service, &raw);
    NSData *edid = CFBridgingRelease(raw);
    if (status != kIOReturnSuccess || edid.length < 12) return false;
    const uint8_t *bytes = edid.bytes;
    *vendor = (uint32_t)bytes[8] << 8 | bytes[9];
    *product = (uint32_t)bytes[11] << 8 | bytes[10];
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
