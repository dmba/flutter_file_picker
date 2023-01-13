//
//  FileUtils.m
//  file_picker
//
//  Created by Miguel Ruivo on 05/12/2018.
//

#import "FileUtils.h"
#import "FileInfo.h"

@implementation FileUtils

+ (BOOL) clearTemporaryFiles {
    NSString *tmpDirectory = NSTemporaryDirectory();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    NSArray *cacheFiles = [fileManager contentsOfDirectoryAtPath:tmpDirectory error:&error];

    for (NSString *file in cacheFiles) {
        error = nil;
        [fileManager removeItemAtPath:[tmpDirectory stringByAppendingPathComponent:file] error:&error];
        if(error != nil) {
            Log(@"Failed to remove temporary file %@, aborting. Error: %@", file, error);
            return false;
        }
    }
    Log(@"All temporary files clear");
    return true;
}

+ (NSArray<NSString*> *) resolveType:(NSString*)type withAllowedExtensions:(NSArray<NSString*>*) allowedExtensions {

    if ([type isEqualToString:@"any"]) {
        return @[@"public.item"];
    } else if ([type isEqualToString:@"image"]) {
        return @[@"public.image"];
    } else if ([type isEqualToString:@"video"]) {
        return @[@"public.movie"];
    } else if ([type isEqualToString:@"audio"]) {
        return @[@"public.audio"];
    } else if ([type isEqualToString:@"media"]) {
        return @[@"public.image", @"public.video"];
    } else if ([type isEqualToString:@"custom"]) {
        if(allowedExtensions == (id)[NSNull null] || allowedExtensions.count == 0) {
            return nil;
        }

        NSMutableArray<NSString*>* utis = [[NSMutableArray<NSString*> alloc] init];

        for(int i = 0 ; i<allowedExtensions.count ; i++) {
            NSString * format = [NSString stringWithFormat:@"dummy.%@", allowedExtensions[i]];
            CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[format pathExtension], NULL);
            NSString * UTIString = (__bridge NSString *)(UTI);
            if (UTI) CFRelease(UTI);
            if (!UTI) {
                Log(@"[Skipping type] Resolving type from extension is not supported: %@", allowedExtensions[i]);
                continue;
            } else if ([UTIString containsString:@"dyn."]) {
                Log(@"[Skipping type] Unsupported file type: %@", UTIString);
                continue;
            } else {
                Log(@"Custom file type supported: %@", UTIString);
                [utis addObject: UTIString];
            }
        }
        return utis;
    } else {
        return nil;
    }
}

+ (MediaType) resolveMediaType:(NSString *)type {
    if([type isEqualToString:@"video"]) {
        return VIDEO;
    } else if([type isEqualToString:@"image"]) {
        return IMAGE;
    } else {
        return MEDIA;
    }
}

+ (NSArray<NSDictionary *> *)resolveFileInfo:(NSArray<NSURL *> *)urls withData: (BOOL)loadData {

    if(urls == nil) {
        return nil;
    }

    NSMutableArray * files = [[NSMutableArray alloc] initWithCapacity:urls.count];

    for(NSURL * url in urls) {
        NSString * path = (NSString *)[url path];
        NSDictionary<NSFileAttributeKey, id> * fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];

        [files addObject: [[[FileInfo alloc] initWithPath: path
                                                   andUrl: url
                                                  andName: [path lastPathComponent]
                                                  andSize: [NSNumber numberWithLongLong: [@(fileAttributes.fileSize) longLongValue]]
                                                  andData: loadData ? [NSData dataWithContentsOfFile:path options: 0 error:nil] : nil] toData]];
    }

    return files;
}

+ (NSURL*) exportMusicAsset:(NSString*) url withName:(NSString *)name {
    AVURLAsset *songAsset = [AVURLAsset URLAssetWithURL: (NSURL*)url options:nil];
    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset: songAsset
                                                                      presetName:AVAssetExportPresetAppleM4A];

    exporter.outputFileType =   @"com.apple.m4a-audio";

    NSString* savePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[name stringByAppendingString:@".m4a"]];
    NSURL *exportURL = [NSURL fileURLWithPath:savePath];

    if ([[NSFileManager defaultManager] fileExistsAtPath:savePath]) {
        return exportURL;
    }

    exporter.outputURL = exportURL;

    dispatch_queue_t queue = dispatch_queue_create("exportQueue", 0);

    dispatch_async(queue, ^{

        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [exporter exportAsynchronouslyWithCompletionHandler:
         ^{

            switch (exporter.status)
            {
                case AVAssetExportSessionStatusFailed:
                {
                    NSError *exportError = exporter.error;
                    Log(@"AVAssetExportSessionStatusFailed: %@", exportError);
                    break;
                }
                case AVAssetExportSessionStatusCompleted:
                {
                    Log(@"AVAssetExportSessionStatusCompleted");
                    @autoreleasepool {
                        dispatch_semaphore_signal(semaphore);
                    }

                    break;
                }
                case AVAssetExportSessionStatusCancelled:
                {
                    Log(@"AVAssetExportSessionStatusCancelled");
                    @autoreleasepool {
                        dispatch_semaphore_signal(semaphore);
                    }
                    break;
                }
                default:
                {
                    Log(@"didn't get export status");
                    break;
                }
            }
        }];

        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    });
    return exportURL;
}

+ (NSString *)resolveImageExtension:(NSString *)url {
    NSData* data = [NSData dataWithContentsOfFile:url options: 0 error:nil];
    char bytes[12] = {0};
    [data getBytes:&bytes length:12];

    const char bmp[2] = {'B', 'M'};
    const char gif[3] = {'G', 'I', 'F'};
    const char swf[3] = {'F', 'W', 'S'};
    const char swc[3] = {'C', 'W', 'S'};
    const char jpg[3] = {0xff, 0xd8, 0xff};
    const char psd[4] = {'8', 'B', 'P', 'S'};
    const char iff[4] = {'F', 'O', 'R', 'M'};
    const char webp[4] = {'R', 'I', 'F', 'F'};
    const char ico[4] = {0x00, 0x00, 0x01, 0x00};
    const char tif_ii[4] = {'I','I', 0x2A, 0x00};
    const char tif_mm[4] = {'M','M', 0x00, 0x2A};
    const char png[8] = {0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a};
    const char jp2[12] = {0x00, 0x00, 0x00, 0x0c, 0x6a, 0x50, 0x20, 0x20, 0x0d, 0x0a, 0x87, 0x0a};


    if (!memcmp(bytes, bmp, 2)) {
        return @"image/x-ms-bmp";
    } else if (!memcmp(bytes, gif, 3)) {
        return @"image/gif";
    } else if (!memcmp(bytes, jpg, 3)) {
        return @"image/jpeg";
    } else if (!memcmp(bytes, psd, 4)) {
        return @"image/psd";
    } else if (!memcmp(bytes, iff, 4)) {
        return @"image/iff";
    } else if (!memcmp(bytes, webp, 4)) {
        return @"image/webp";
    } else if (!memcmp(bytes, ico, 4)) {
        return @"image/vnd.microsoft.icon";
    } else if (!memcmp(bytes, tif_ii, 4) || !memcmp(bytes, tif_mm, 4)) {
        return @"image/tiff";
    } else if (!memcmp(bytes, png, 8)) {
        return @"image/png";
    } else if (!memcmp(bytes, jp2, 12)) {
        return @"image/jp2";
    }

    return @"application/octet-stream"; // default type

}

@end
