#import "CEProvider.h"

#import <Foundation/Foundation.h>
#import <os/log.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMediaIO/CMIOHardware.h>
#import <IOKit/audio/IOAudioTypes.h>

#import "addMethod.h"

// #define OSC_DEBUG
#ifdef OSC_DEBUG
    #import "OSC.h"
    OSC::Sender *sender = new OSC::Sender("127.0.0.1",54321);
#endif

@class CEStreamSource;

#define kFrameRate 30
#define kLable "timerQueue"
#define kStream @"SampleCapture.Video"
#define kModel @"SampleCapture Model"
#define kDevice @"Sample Capture (Objective-C)"
#define kManufacturer @"SampleCapture Manufacturer"

#pragma mark -

@interface CEDeviceSource : NSObject<CMIOExtensionDeviceSource> {
	CEStreamSource *_streamSource;
	uint32_t _streamingCounter;
	dispatch_source_t _timer;
	CMFormatDescriptionRef _videoDescription;
	CVPixelBufferPoolRef _bufferPool;
	NSDictionary *_bufferAuxAttributes;
	uint32_t _whiteStripeStartRow;
	BOOL _whiteStripeIsAscending;
    id<AVCaptureVideoDataOutputSampleBufferDelegate> _observer;
    AVCaptureSession *_session;
    AVCaptureDeviceInput *_videoDeviceInput;
    AVCaptureVideoDataOutput *_dataOutput;
}

+(instancetype)deviceWithLocalizedName:(NSString *)localizedName;
-(instancetype)initWithLocalizedName:(NSString *)localizedName;

@property(nonatomic, readonly) CMIOExtensionDevice *device;
@property(nonatomic, strong) __attribute__((NSObject)) CMFormatDescriptionRef videoDescription;
@property(nonatomic, strong) __attribute__((NSObject)) CVPixelBufferPoolRef bufferPool;
@property(nonatomic, strong) NSDictionary *bufferAuxAttributes;
@property(nonatomic, readonly) dispatch_queue_t timerQueue;

-(void)startStreaming;
-(void)stopStreaming;

@end

#pragma mark -

@interface CEStreamSource : NSObject<CMIOExtensionStreamSource> {
	__unsafe_unretained CMIOExtensionDevice *_device;
	CMIOExtensionStreamFormat *_streamFormat;
	NSUInteger _activeFormatIndex;
}

-(instancetype)initWithLocalizedName:(NSString *)localizedName streamID:(NSUUID *)streamID streamFormat:(CMIOExtensionStreamFormat *)streamFormat device:(CMIOExtensionDevice *)device;

@property(nonatomic, readonly) CMIOExtensionStream *stream;

@end

#pragma mark -

@implementation CEDeviceSource

+(instancetype)deviceWithLocalizedName:(NSString *)localizedName {
	return [[[self class] alloc] initWithLocalizedName:localizedName];
}

-(instancetype)initWithLocalizedName:(NSString *)localizedName {
    
	self = [super init];
	if(self) {
        
        CMVideoDimensions dims = {.width = 640, .height = 480};

        NSString *name = @"Apple Inc.";                   
        AVCaptureDeviceDiscoverySession *captureDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position: AVCaptureDevicePositionUnspecified];
        NSArray *devices = [captureDeviceDiscoverySession devices];
                   
        int select = -1;
       
        if(devices) {
            
           unsigned long num = [devices count];
           if(num>0) {
               for(int k=0; k<num; k++) {
                   AVCaptureDevice *device = (AVCaptureDevice *)devices[k];
                   if([device hasMediaType:AVMediaTypeVideo]) {
                       if([device.manufacturer compare:name]==NSOrderedSame) {
                           select = k;
                           break;
                       }
                   }
               }
           }
           
           if(select!=-1) {
               
               AVCaptureDevice *device = devices[select];
               NSArray<AVCaptureDeviceFormat *> *formats = device.formats;
               
               for(int k=0; k<[formats count]; k++) {
                                   
                   AVCaptureDeviceFormat *format = formats[k];
                   CMFormatDescriptionRef desc = format.formatDescription;
                   CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(desc);

                   if(dims.width==dimensions.width&&dims.height==dimensions.height) {
                       
                       objc_registerClassPair(objc_allocateClassPair(objc_getClass("NSObject"),"AVCaptureVideoDataOutputSampleBuffer",0));
                                   Class AVCaptureVideoDataOutputSampleBuffer = objc_getClass("AVCaptureVideoDataOutputSampleBuffer");

                       addMethod(AVCaptureVideoDataOutputSampleBuffer,@"captureOutput:didOutputSampleBuffer:fromConnection:",^(id me,AVCaptureOutput *captureOutput, CMSampleBufferRef sampleBuffer,AVCaptureConnection *connection) {
                           
                               
                           CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                           CVPixelBufferRef pixelBuffer = NULL;
                           OSStatus err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, self.bufferPool,(__bridge CFDictionaryRef)self.bufferAuxAttributes,&pixelBuffer);
                           
                           if(!err&&imageBuffer&&pixelBuffer) {
                               
                               CVPixelBufferLockBaseAddress(pixelBuffer,0);
                               CVPixelBufferLockBaseAddress(imageBuffer,0);
                               {
                                   unsigned int *pixel = (unsigned int *)CVPixelBufferGetBaseAddress(pixelBuffer);
                                   size_t width = CVPixelBufferGetWidth(pixelBuffer);
                                   size_t height = CVPixelBufferGetHeight(pixelBuffer);
                                                                          
                                   size_t rowBytes[2] = {
                                       (CVPixelBufferGetBytesPerRow(imageBuffer))>>2,
                                       (CVPixelBufferGetBytesPerRow(pixelBuffer))>>2
                                   };
                                   
                                   if(width==CVPixelBufferGetWidth(imageBuffer)&&height==CVPixelBufferGetHeight(imageBuffer)) {
                                       
                                       unsigned int *image = (unsigned int *)CVPixelBufferGetBaseAddress(imageBuffer);

                                       for(int i=0; i<height; i++) {
                                           for(int j=0; j<width; j++) {
                                               pixel[i*rowBytes[0]+j] = image[i*rowBytes[1]+j];
                                           }
                                       }
                                   }
                                   else {
                                       unsigned int color = 0xFF000000|(random()&0xFFFFFF);
                                       for(int i=0; i<height; i++) {
                                           for(int j=0; j<width; j++) {
                                               pixel[i*rowBytes[0]+j] = color;
                                           }
                                       }
                                   }
                               }
                               CVPixelBufferUnlockBaseAddress(imageBuffer,0);
                               CVPixelBufferUnlockBaseAddress(pixelBuffer,0);

                               CMSampleBufferRef sbuf = NULL;
                               CMSampleTimingInfo timing;
                               timing.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock());
                               timing.decodeTimeStamp = kCMTimeInvalid;
                               
                               err = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, NULL, NULL, self.videoDescription, &timing, &sbuf);
                               CFRelease(pixelBuffer);
                               if(!err) {
                                   [self->_streamSource.stream sendSampleBuffer:sbuf discontinuity:CMIOExtensionStreamDiscontinuityFlagTime hostTimeInNanoseconds:0];
                                   CFRelease(sbuf);
                               }
                           }
                           
                       },"v@:@@@");
                                   
                       _observer = [[AVCaptureVideoDataOutputSampleBuffer alloc] init];

                       _videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];

                       _dataOutput = [[AVCaptureVideoDataOutput alloc] init];
                       _dataOutput.videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithFloat:dims.width],(id)kCVPixelBufferWidthKey,
                          [NSNumber numberWithFloat:dims.height],(id)kCVPixelBufferHeightKey,
                          [NSNumber numberWithInt:kCVPixelFormatType_32BGRA],(id)kCVPixelBufferPixelFormatTypeKey,
                       nil];
                       
                       [_dataOutput setSampleBufferDelegate:_observer queue:dispatch_queue_create("org.mizt.vdig",nullptr)];
                
                       break;
                   }
               }
           }
       }

		NSUUID *deviceID = [[NSUUID alloc] init]; // replace this with your device UUID
		_device = [[CMIOExtensionDevice alloc] initWithLocalizedName:localizedName deviceID:deviceID legacyDeviceID:nil source:self];
        _streamingCounter = 0;
		_timerQueue = dispatch_queue_create(kLable,0);
		(void)CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCVPixelFormatType_32BGRA, dims.width, dims.height, NULL, &_videoDescription);
		if (_videoDescription) {
			NSDictionary *pixelBufferAttributes = @{
                (id)kCVPixelBufferWidthKey:@(dims.width),
                (id)kCVPixelBufferHeightKey:@(dims.height),
                (id)kCVPixelBufferPixelFormatTypeKey : @(CMFormatDescriptionGetMediaSubType(_videoDescription)),
                (id)kCVPixelBufferIOSurfacePropertiesKey:@{},
            };
            
			(void)CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)pixelBufferAttributes, &_bufferPool);
		}
        		
		CMIOExtensionStreamFormat *videoStreamFormat = nil;
		if(_bufferPool) {
			videoStreamFormat = [[CMIOExtensionStreamFormat alloc] initWithFormatDescription:_videoDescription maxFrameDuration:CMTimeMake(1,kFrameRate) minFrameDuration:CMTimeMake(1,kFrameRate) validFrameDurations:nil];
			_bufferAuxAttributes = @{(id)kCVPixelBufferPoolAllocationThresholdKey:@(15)};
		}
		
		if(videoStreamFormat) {
			NSUUID *videoID = [[NSUUID alloc] init]; // replace this with your video UUID
			_streamSource = [[CEStreamSource alloc] initWithLocalizedName:kStream streamID:videoID streamFormat:videoStreamFormat device:_device];
			
			NSError *error = nil;
			if (![_device addStream:_streamSource.stream error:&error]) {
				@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Failed to add stream: %@", error.localizedDescription] userInfo:nil];
			}
		}
	}
	return self;
}

-(NSSet<CMIOExtensionProperty> *)availableProperties {
    return [NSSet setWithObjects:CMIOExtensionPropertyDeviceTransportType, CMIOExtensionPropertyDeviceModel, nil];
}

-(nullable CMIOExtensionDeviceProperties *)devicePropertiesForProperties:(NSSet<CMIOExtensionProperty> *)properties error:(NSError * _Nullable *)outError {
	CMIOExtensionDeviceProperties *deviceProperties = [CMIOExtensionDeviceProperties devicePropertiesWithDictionary:@{}];
	if([properties containsObject:CMIOExtensionPropertyDeviceTransportType]) {
		deviceProperties.transportType = [NSNumber numberWithInt:kIOAudioDeviceTransportTypeVirtual];
	}
	if([properties containsObject:CMIOExtensionPropertyDeviceModel]) {
		deviceProperties.model = kModel;
	}
	return deviceProperties;
}

-(BOOL)setDeviceProperties:(CMIOExtensionDeviceProperties *)deviceProperties error:(NSError * _Nullable *)outError {
	return YES;
}

- (void)startStreaming {
    
	if(!_bufferPool) return;

	_streamingCounter++;
    if(_streamingCounter==1) {
        if(_observer) {
            if(_session==nil) {
                _session = [[AVCaptureSession alloc] init];
                [_session addInput:_videoDeviceInput];
                [_session addOutput:_dataOutput];
                _session.sessionPreset = AVCaptureSessionPreset640x480;
                [_session startRunning];
            }
        }
        else {
            if(_timer==nil) {
                
#ifdef OSC_DEBUG
                sender->send("/debug","s","start");
#endif
                
                
                // else {}
                
                _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,_timerQueue);
                dispatch_source_set_timer(_timer,DISPATCH_TIME_NOW,(uint64_t)(NSEC_PER_SEC/kFrameRate),0);
                dispatch_source_set_event_handler(_timer,^{
                    dispatch_async(dispatch_get_main_queue(),^{
                        
                        CVPixelBufferRef pixelBuffer = NULL;
                        OSStatus err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, self.bufferPool,(__bridge CFDictionaryRef)self.bufferAuxAttributes,&pixelBuffer);
                        
                        if(!err&&pixelBuffer) {
                            
                            CVPixelBufferLockBaseAddress(pixelBuffer,0);
                            {
                                unsigned int *bufferPtr = (unsigned int *)CVPixelBufferGetBaseAddress(pixelBuffer);
                                size_t width = CVPixelBufferGetWidth(pixelBuffer);
                                size_t height = CVPixelBufferGetHeight(pixelBuffer);
                                size_t rowBytes = (CVPixelBufferGetBytesPerRow(pixelBuffer))>>2;
                                
                                unsigned int color = 0xFF000000|(random()&0xFFFFFF);
                                
                                for(int i=0; i<height; i++) {
                                    for(int j=0; j<width; j++) {
                                        bufferPtr[i*rowBytes+j] = color;
                                    }
                                }
                                
                            }
                            CVPixelBufferUnlockBaseAddress(pixelBuffer,0);
                            
                            CMSampleBufferRef sbuf = NULL;
                            CMSampleTimingInfo timing;
                            timing.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock());
                            timing.decodeTimeStamp = kCMTimeInvalid;
                            
                            err = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, NULL, NULL, self.videoDescription, &timing, &sbuf);
                            CFRelease(pixelBuffer);
                            if(!err) {
                                [self->_streamSource.stream sendSampleBuffer:sbuf discontinuity:CMIOExtensionStreamDiscontinuityFlagTime hostTimeInNanoseconds:0];
                                CFRelease(sbuf);
                            }
                        }
                    });
                });
                
                dispatch_source_set_cancel_handler(_timer,^{});
                dispatch_resume(_timer);
            }
        }
    }
}

-(void)stopStreaming {
    _streamingCounter--;
	if(_streamingCounter==0) {
#ifdef OSC_DEBUG
        sender->send("/debug","s","stop");
#endif
        if(_session!=nil) {
            [_session stopRunning];
            _session = nil;
        }
        
        if(_timer) {
            dispatch_source_cancel(_timer);
            _timer = nil;
        }
	}
}

@end

#pragma mark -

@implementation CEStreamSource

- (instancetype)initWithLocalizedName:(NSString *)localizedName streamID:(NSUUID *)streamID streamFormat:(CMIOExtensionStreamFormat *)streamFormat device:(CMIOExtensionDevice *)device {
	self = [super init];
	if(self) {
		_device = device;
		_streamFormat = streamFormat;
		_stream = [[CMIOExtensionStream alloc] initWithLocalizedName:localizedName streamID:streamID direction:CMIOExtensionStreamDirectionSource clockType:CMIOExtensionStreamClockTypeHostTime source:self];
	}
	return self;
}

-(NSArray<CMIOExtensionStreamFormat *> *)formats {
	return [NSArray arrayWithObjects:_streamFormat, nil];
}

-(NSUInteger)activeFormatIndex {
	return 0;
}

-(void)setActiveFormatIndex:(NSUInteger)activeFormatIndex {
	if(activeFormatIndex >= 1) os_log_error(OS_LOG_DEFAULT,"Invalid index");
}

-(NSSet<CMIOExtensionProperty> *)availableProperties {
    return [NSSet setWithObjects:CMIOExtensionPropertyStreamActiveFormatIndex, CMIOExtensionPropertyStreamFrameDuration, nil];
}

- (nullable CMIOExtensionStreamProperties *)streamPropertiesForProperties:(NSSet<CMIOExtensionProperty> *)properties error:(NSError * _Nullable *)outError {
    
	CMIOExtensionStreamProperties *streamProperties = [CMIOExtensionStreamProperties streamPropertiesWithDictionary:@{}];
	if([properties containsObject:CMIOExtensionPropertyStreamActiveFormatIndex]) {
		streamProperties.activeFormatIndex = @(self.activeFormatIndex);
	}
	if([properties containsObject:CMIOExtensionPropertyStreamFrameDuration]) {
		CMTime frameDuration = CMTimeMake(1, kFrameRate);
		NSDictionary *frameDurationDictionary = CFBridgingRelease(CMTimeCopyAsDictionary(frameDuration, NULL));
		streamProperties.frameDuration = frameDurationDictionary;
	}
	return streamProperties;
}

-(BOOL)setStreamProperties:(CMIOExtensionStreamProperties *)streamProperties error:(NSError * _Nullable *)outError {
	if(streamProperties.activeFormatIndex) {
		[self setActiveFormatIndex:streamProperties.activeFormatIndex.unsignedIntegerValue];
	}
	return YES;
}

-(BOOL)authorizedToStartStreamForClient:(CMIOExtensionClient *)client {
	return YES;
}

-(BOOL)startStreamAndReturnError:(NSError * _Nullable *)outError {
	CEDeviceSource *deviceSource = (CEDeviceSource *)_device.source;
	[deviceSource startStreaming];
	return YES;
}

-(BOOL)stopStreamAndReturnError:(NSError * _Nullable *)outError {
	CEDeviceSource *deviceSource = (CEDeviceSource *)_device.source;
	[deviceSource stopStreaming];
	return YES;
}

@end

#pragma mark -

@interface CEProviderSource() {
	CEDeviceSource *_deviceSource;
}
@end

@implementation CEProviderSource

-(instancetype)initWithClientQueue:(dispatch_queue_t)clientQueue {
	self = [super init];
	if (self) {
		_provider = [[CMIOExtensionProvider alloc] initWithSource:self clientQueue:clientQueue];
		_deviceSource = [[CEDeviceSource alloc] initWithLocalizedName:kDevice];
		NSError *error = nil;
		if(![_provider addDevice:_deviceSource.device error:&error]) {
			@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Failed to add device: %@",error.localizedDescription] userInfo:nil];
		}
	}
	return self;
}

-(BOOL)connectClient:(CMIOExtensionClient *)client error:(NSError * _Nullable *)outError {
	return YES;
}

-(void)disconnectClient:(CMIOExtensionClient *)client {
}

-(NSSet<CMIOExtensionProperty> *)availableProperties {
    return [NSSet setWithObjects:CMIOExtensionPropertyProviderManufacturer,nil];
}

-(nullable CMIOExtensionProviderProperties *)providerPropertiesForProperties:(NSSet<CMIOExtensionProperty> *)properties error:(NSError * _Nullable *)outError {
	CMIOExtensionProviderProperties *providerProperties = [CMIOExtensionProviderProperties providerPropertiesWithDictionary:@{}];
	if([properties containsObject:CMIOExtensionPropertyProviderManufacturer]) {
		providerProperties.manufacturer = kManufacturer;
	}
	return providerProperties;
}

-(BOOL)setProviderProperties:(CMIOExtensionProviderProperties *)providerProperties error:(NSError * _Nullable *)outError {
	return YES;
}

@end
