#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include "recorder.h"
#include <string.h>

@interface Recorder : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (strong) AVCaptureSession *capture;
@property (strong) AVCaptureVideoDataOutput *output;
@property (strong) AVAssetWriter *writer;
@property (strong) AVAssetWriterInput *input;
@property (strong) NSURL *url;
@property (strong) dispatch_queue_t queue;
@property (copy) NSString *failure;
@property BOOL firstFrame;
@property BOOL stopping;
@property (strong) id runtimeObserver;
@end

@implementation Recorder
- (void)fail:(NSString *)message {
 @synchronized (self) { if (!_failure) _failure = [message copy]; }
}
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sample fromConnection:(AVCaptureConnection *)connection {
 (void)output; (void)connection;
 if (self.stopping || !CMSampleBufferDataIsReady(sample)) return;
 if (!self.firstFrame) {
  CVImageBufferRef image = CMSampleBufferGetImageBuffer(sample);
  if (!image) { [self fail:@"First frame has no image buffer"]; return; }
  size_t width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image);
  // H.264 requires even dimensions on common encoders.
  width &= ~(size_t)1; height &= ~(size_t)1;
  if (!width || !height) { [self fail:@"Invalid first frame dimensions"]; return; }
  NSError *error = nil;
  self.writer = [[AVAssetWriter alloc] initWithURL:self.url fileType:AVFileTypeMPEG4 error:&error];
  if (!self.writer) { [self fail:[NSString stringWithFormat:@"Cannot create MP4 writer: %@", error]]; return; }
  NSDictionary *settings = @{ AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(width), AVVideoHeightKey: @(height) };
  self.input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
  self.input.expectsMediaDataInRealTime = YES;
  if (![self.writer canAddInput:self.input]) { [self fail:@"H.264 writer cannot accept video input"]; return; }
  [self.writer addInput:self.input];
  if (![self.writer startWriting]) { [self fail:[NSString stringWithFormat:@"Cannot start H.264 writer: %@", self.writer.error]]; return; }
  CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
  if (!CMTIME_IS_VALID(pts)) { [self fail:@"First frame has invalid timestamp"]; return; }
  [self.writer startSessionAtSourceTime:pts];
  @synchronized (self) { self.firstFrame = YES; }
 }
 if (self.writer.status == AVAssetWriterStatusFailed) { [self fail:[NSString stringWithFormat:@"Encoder failed: %@", self.writer.error]]; return; }
 if (self.input.readyForMoreMediaData && ![self.input appendSampleBuffer:sample])
  [self fail:[NSString stringWithFormat:@"Failed to encode video frame: %@", self.writer.error]];
}
@end
static Recorder *recorder;
static char errorBuffer[4096];
static void setError(NSString *s) { snprintf(errorBuffer, sizeof(errorBuffer), "%s", (s ?: @"Unknown error").UTF8String); }
const char *rec_error(void) { return errorBuffer; }
int rec_start(const char *path) {
 @autoreleasepool {
  errorBuffer[0] = 0;
  if (!CGPreflightScreenCaptureAccess() && !CGRequestScreenCaptureAccess()) {
   setError(@"Screen recording permission denied. Enable it for your terminal in System Settings > Privacy & Security > Screen Recording, then restart the terminal."); return 0;
  }
  Recorder *r = [Recorder new]; r.url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
  r.queue = dispatch_queue_create("screenrec.frames", DISPATCH_QUEUE_SERIAL);
  r.capture = [AVCaptureSession new];
  AVCaptureScreenInput *input = [[AVCaptureScreenInput alloc] initWithDisplayID:CGMainDisplayID()];
  if (!input) { setError(@"Cannot create main display capture input"); return 0; }
  input.minFrameDuration = CMTimeMake(1, 30); input.capturesCursor = YES;
  if (![r.capture canAddInput:input]) { setError(@"Cannot add screen capture input"); return 0; }
  [r.capture addInput:input];
  r.output = [AVCaptureVideoDataOutput new]; r.output.alwaysDiscardsLateVideoFrames = YES;
  r.output.videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA) };
  [r.output setSampleBufferDelegate:r queue:r.queue];
  if (![r.capture canAddOutput:r.output]) { setError(@"Cannot add video capture output"); return 0; }
  [r.capture addOutput:r.output];
  __weak Recorder *weakR = r;
  r.runtimeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:r.capture queue:nil usingBlock:^(NSNotification *note) {
   [weakR fail:[NSString stringWithFormat:@"Capture error: %@", note.userInfo[AVCaptureSessionErrorKey]]];
  }];
  recorder = r; [r.capture startRunning];
  if (!r.capture.isRunning) { [r fail:@"Screen capture failed to start"]; setError(r.failure); rec_stop(); return 0; }
  return 1;
 }
}
int rec_failed(void) {
 @autoreleasepool { Recorder *r = recorder; if (!r) return 1;
  @synchronized (r) { if (r.failure) { setError(r.failure); return 1; } }
  return 0;
 }
}
int rec_has_frame(void) { Recorder *r = recorder; if (!r) return 0; @synchronized (r) { return r.firstFrame; } }
int rec_stop(void) {
 @autoreleasepool {
  Recorder *r = recorder; if (!r) return 0;
  [r.capture stopRunning];
  dispatch_sync(r.queue, ^{ r.stopping = YES; });
  if (r.runtimeObserver) [[NSNotificationCenter defaultCenter] removeObserver:r.runtimeObserver];
  if (!r.firstFrame && !r.failure) [r fail:@"No screen frame received; check permission and try again"];
  if (r.writer && r.writer.status == AVAssetWriterStatusWriting) {
   [r.input markAsFinished];
   dispatch_semaphore_t done = dispatch_semaphore_create(0);
   [r.writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
   if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30LL * NSEC_PER_SEC)) != 0)
    [r fail:@"Timed out finalizing MP4; output may be incomplete"];
   else if (r.writer.status != AVAssetWriterStatusCompleted)
    [r fail:[NSString stringWithFormat:@"Failed to finalize MP4: %@", r.writer.error]];
  } else if (r.writer && r.writer.status == AVAssetWriterStatusFailed) {
   [r fail:[NSString stringWithFormat:@"Encoder failed: %@", r.writer.error]];
  }
  NSString *failure; @synchronized (r) { failure = r.failure; }
  if (failure) setError(failure);
  recorder = nil; return failure ? 0 : 1;
 }
}


