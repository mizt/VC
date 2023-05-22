#import "CEProvider.h"

#import <Foundation/Foundation.h>
#import <os/log.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMediaIO/CMIOHardware.h>
#import <IOKit/audio/IOAudioTypes.h>

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
		NSUUID *deviceID = [[NSUUID alloc] init]; // replace this with your device UUID
		_device = [[CMIOExtensionDevice alloc] initWithLocalizedName:localizedName deviceID:deviceID legacyDeviceID:nil source:self];
        _streamingCounter = 0;
		_timerQueue = dispatch_queue_create(kLable,0);
		CMVideoDimensions dims = {.width = 640, .height = 480};
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
    if(_timer==nil) {
        
#ifdef OSC_DEBUG
        sender->send("/debug","s","start");
#endif
        
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,_timerQueue);
        dispatch_source_set_timer(_timer,DISPATCH_TIME_NOW,(uint64_t)(NSEC_PER_SEC/kFrameRate),0);
        dispatch_source_set_event_handler(_timer, ^{
            dispatch_async(dispatch_get_main_queue(),^{
                     
                CVPixelBufferRef pixelBuffer = NULL;
                OSStatus err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, self.bufferPool, (__bridge CFDictionaryRef)self.bufferAuxAttributes, &pixelBuffer );
                
                if(!err&&pixelBuffer) {
                    
                    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
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

-(void)stopStreaming {
    _streamingCounter--;
	if(_streamingCounter==0) {
            
#ifdef OSC_DEBUG
        sender->send("/debug","s","stop");
#endif
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
