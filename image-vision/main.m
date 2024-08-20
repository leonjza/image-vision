#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <AppKit/AppKit.h>

typedef NS_ENUM(NSUInteger, OutputMode) {
    OutputModeSeparateFiles,
    OutputModeSingleFile,
    OutputModeJSON
};

OutputMode outputMode = OutputModeSeparateFiles;
NSString *outputFilePath = nil;
NSMutableDictionary *jsonOutput = nil;

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
    
    // Create a text recognition request
    VNRecognizeTextRequest *textRequest = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
        if (error) {
            print([NSString stringWithFormat:@"Error recognizing text: %@", error.localizedDescription]);
            return;
        }
        
        NSMutableString *recognizedText = [NSMutableString string];
        NSUInteger wordCount = 0;
        
        for (VNRecognizedTextObservation *observation in request.results) {
            if (![observation isKindOfClass:[VNRecognizedTextObservation class]]) {
                continue;
            }
            
            // Extract the top candidate text
            VNRecognizedText *topCandidate = [observation topCandidates:1].firstObject;
            if (topCandidate) {
                [recognizedText appendFormat:@"%@ ", topCandidate.string];
                wordCount += [[topCandidate.string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] count];
            }
        }
        
        // Output the recognized text based on the selected mode
        if (outputMode == OutputModeSeparateFiles) {
            NSString *outputFileName = [[filePath stringByDeletingPathExtension] stringByAppendingString:@"-image-vision.txt"];
            [[NSFileManager defaultManager] createFileAtPath:outputFileName contents:nil attributes:nil];
            NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:outputFileName];
            if (fileHandle) {
                print([NSString stringWithFormat:@"%8lu words recognized, writing to %@", (unsigned long)wordCount, outputFileName]);
                [fileHandle writeData:[recognizedText dataUsingEncoding:NSUTF8StringEncoding]];
                [fileHandle closeFile];
            } else {
                print([NSString stringWithFormat:@"Failed to create file at path: %@", outputFileName]);
            }
        } else if (outputMode == OutputModeSingleFile) {
            NSString *outputString = [NSString stringWithFormat:@"\n%@\n%@\n", [filePath lastPathComponent], recognizedText];
            NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:outputFilePath];
            if (fileHandle) {
                [fileHandle seekToEndOfFile];
                [fileHandle writeData:[outputString dataUsingEncoding:NSUTF8StringEncoding]];
                [fileHandle closeFile];
            } else {
                print([NSString stringWithFormat:@"Failed to write to file: %@", outputFilePath]);
            }
        } else if (outputMode == OutputModeJSON) {
            jsonOutput[[filePath lastPathComponent]] = [recognizedText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
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
            NSString *usage = [NSString stringWithFormat:@"Usage: %@ /path/to/your/directory/of/images [--single-file output.txt] [--json output.json]", binaryName];
            print(usage);
            return -1;
        }
        
        NSString *directoryPath = [NSString stringWithUTF8String:argv[1]];
        BOOL isDirectory;
        if (![[NSFileManager defaultManager] fileExistsAtPath:directoryPath isDirectory:&isDirectory] || !isDirectory) {
            print(@"The provided path is not a valid directory.");
            return -1;
        }
        
        // Handle command-line arguments for output mode
        for (int i = 2; i < argc; i++) {
            if (strcmp(argv[i], "--single-file") == 0 && i + 1 < argc) {
                outputMode = OutputModeSingleFile;
                outputFilePath = [NSString stringWithUTF8String:argv[i + 1]];
                [[NSFileManager defaultManager] createFileAtPath:outputFilePath contents:nil attributes:nil];
                i++; // Skip the next argument since it's the file path
            } else if (strcmp(argv[i], "--json") == 0 && i + 1 < argc) {
                outputMode = OutputModeJSON;
                outputFilePath = [NSString stringWithUTF8String:argv[i + 1]];
                jsonOutput = [NSMutableDictionary dictionary];
                i++; // Skip the next argument since it's the file path
            }
        }

        // Scan the directory for images and process them
        scanDirectoryForSupportedImages(directoryPath);

        // If in JSON mode, write the output to the specified file
        if (outputMode == OutputModeJSON && jsonOutput) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonOutput options:NSJSONWritingPrettyPrinted error:nil];
            [jsonData writeToFile:outputFilePath atomically:YES];
            print([NSString stringWithFormat:@"JSON output written to %@", outputFilePath]);
        }
    }
    return 0;
}
