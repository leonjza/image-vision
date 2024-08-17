#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <AppKit/AppKit.h>

void print(NSString *message) {
    printf("%s\n", [message UTF8String]);
}

void processImage(NSString *filePath) {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:filePath];
    if (!image) {
        print([NSString stringWithFormat:@"Failed to load image from path: %@", filePath]);
        return;
    }
        
    // Convert NSImage to CGImage
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)[image TIFFRepresentation], NULL);
    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    if (!cgImage) {
        print(@"Failed to convert NSImage to CGImage.");
        CFRelease(source);
        return;
    }
    
    // Create a VNImageRequestHandler
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
    
    // Create the output file path
    NSString *outputFileName = [[filePath stringByDeletingPathExtension] stringByAppendingString:@"-image-vision.txt"];
    [[NSFileManager defaultManager] createFileAtPath:outputFileName contents:nil attributes:nil];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:outputFileName];
    
    if (!fileHandle) {
        print([NSString stringWithFormat:@"Failed to create file at path: %@", outputFileName]);
        CGImageRelease(cgImage);
        CFRelease(source);
        return;
    }
    
    // Create a text recognition request
    VNRecognizeTextRequest *textRequest = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
        if (error) {
            print([NSString stringWithFormat:@"Error recognizing text: %@", error.localizedDescription]);
            return;
        }
        
        NSUInteger wordCount = 0;
        
        for (VNRecognizedTextObservation *observation in request.results) {
            if (![observation isKindOfClass:[VNRecognizedTextObservation class]]) {
                continue;
            }
            
            // Extract the top candidate text
            VNRecognizedText *topCandidate = [observation topCandidates:1].firstObject;
            if (topCandidate) {
                // Write the recognized text directly to the file
                NSString *textToWrite = [topCandidate.string stringByAppendingString:@" "];
                [fileHandle writeData:[textToWrite dataUsingEncoding:NSUTF8StringEncoding]];
                
                // Increment word count
                wordCount += [[topCandidate.string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] count];
            }
        }
        
        // Print the word count and output file path
        print([NSString stringWithFormat:@"%8lu words recognized, writing to %@", (unsigned long)wordCount, outputFileName]);
    }];
    
    // Set recognition languages and options
    textRequest.recognitionLanguages = @[@"en"];
    textRequest.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    
    // Perform the request
    NSError *requestError = nil;
    [handler performRequests:@[textRequest] error:&requestError];
    if (requestError) {
        print([NSString stringWithFormat:@"Error performing text recognition request: %@", requestError.localizedDescription]);
    }
    
    // Clean up
    [fileHandle closeFile];
    CGImageRelease(cgImage);
    CFRelease(source);
}

void scanDirectoryForSupportedImages(NSString *directoryPath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    
    // Get all files in the directory
    NSArray *files = [fileManager contentsOfDirectoryAtPath:directoryPath error:&error];
    if (error) {
        print([NSString stringWithFormat:@"Error reading directory: %@", error.localizedDescription]);
        return;
    }
    
    // Filter and sort files alphabetically
    NSArray *supportedExtensions = @[@"png", @"jpg", @"jpeg", @"tiff", @"bmp", @"gif", @"heic"];
    NSArray *sortedFiles = [[files filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *fileName, NSDictionary *bindings) {
        return [supportedExtensions containsObject:[[fileName pathExtension] lowercaseString]];
    }]] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    
    // Process each image file
    for (NSString *file in sortedFiles) {
        NSString *fullFilePath = [directoryPath stringByAppendingPathComponent:file];
        processImage(fullFilePath);
    }
}


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            NSString *binaryName = [[NSProcessInfo processInfo] processName];
            NSLog(@"Usage: %@ /path/to/your/directory/of/images", binaryName);
            return -1;
        }
        
        NSString *directoryPath = [NSString stringWithUTF8String:argv[1]];
        BOOL isDirectory;
        if (![[NSFileManager defaultManager] fileExistsAtPath:directoryPath isDirectory:&isDirectory] || !isDirectory) {
            NSLog(@"The provided path is not a valid directory.");
            return -1;
        }
        
        scanDirectoryForSupportedImages(directoryPath);
    }
    return 0;
}
