#include <CoreFoundation/CoreFoundation.h>
#include <NetFS/NetFS.h>
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 3 || strlen(argv[1]) < 1 || strlen(argv[1]) > 32) return 2;
    for (const unsigned char *p = (const unsigned char *)argv[1]; *p; ++p)
        if (!isalnum(*p) && *p != '_' && *p != '-' && *p != '.') return 2;
    CFStringRef user = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
    CFStringRef address = CFStringCreateWithCString(NULL, argv[2], kCFStringEncodingUTF8);
    CFURLRef url = address ? CFURLCreateWithString(NULL, address, NULL) : NULL;
    if (!url) return 2;
    CFRelease(address);
    CFMutableDictionaryRef options = CFDictionaryCreateMutable(NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    /* NetAuth reuses macOS credentials. No password read, saved, or printed here. */
    CFDictionarySetValue(options, kNAUIOptionKey, kNAUIOptionNoUI);
    CFArrayRef points = NULL;
    alarm(20);
    int result = NetFSMountURLSync(url, NULL, user, NULL, options, NULL, &points);
    alarm(0);
    if (points) CFRelease(points);
    CFRelease(options);
    CFRelease(url);
    CFRelease(user);
    printf("NetFS status: %d\n", result);
    return result == 0 ? 0 : 1;
}
