//
//  ViewController.m
//  iCloudTests
//
//  Created by Barak Yoresh on 31/01/2018.
//  Copyright © 2018 Lightricks. All rights reserved.
//

#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UILabel *stepperLabel;
@property (weak, nonatomic) IBOutlet UIStepper *stepper;
@property (weak, nonatomic) IBOutlet UIButton *fetchButton;
@property (weak, nonatomic) IBOutlet UIButton *ShuffleButton;
@property (weak, nonatomic) IBOutlet UITextView *infoText;
@property (weak, nonatomic) IBOutlet UITextView *assetsTextView;
@property (weak, nonatomic) IBOutlet UIView *playerContainer;
@property (strong, nonatomic) AVPlayerViewController *playerController;
@property (strong, nonatomic) AVPlayerLayer *playerLayer;
@property (weak, nonatomic) IBOutlet UISwitch *apiSwitch;

@property (strong, nonatomic) PHFetchResult<PHAsset *> *videoAssets;
@property (strong, nonatomic) NSArray *assets;
@property (nonatomic) PHImageRequestID lastRequestID;

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  self.playerController = [[AVPlayerViewController alloc] initWithNibName:nil bundle:nil];
  [self addChildViewController:self.playerController];
  [self.playerContainer addSubview:self.playerController.view];
  self.playerController.view.frame = self.playerContainer.bounds;

  self.assets = [NSArray array];
  self.videoAssets = [self fetchVideoAssets];

  self.stepper.maximumValue = self.videoAssets.count;
  self.stepper.value = self.stepper.maximumValue;
  [self.stepper addTarget:self action:@selector(stepperChanged:)
         forControlEvents:UIControlEventValueChanged];

  self.stepperLabel.text = [@(self.stepper.value) description];

  self.lastRequestID = -1;
}

- (void)stepperChanged:(UIStepper *)stepper {
  self.stepperLabel.text = [@(stepper.value) description];
}

- (IBAction)fetchTapped:(id)sender {
  if (self.lastRequestID != -1) {
    NSLog(@"Cancelling last request id");
    [[PHImageManager defaultManager] cancelImageRequest:self.lastRequestID];
  }

  NSUInteger index = ((int)(self.stepper.value)) - 1;
  NSLog(@"Fetching asset #%lu", index);
  PHAsset *asset = self.videoAssets[index];
  NSLog(@"Fetching AVAsset for asset %@", asset);
  PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
  options.networkAccessAllowed = YES;
  options.progressHandler = ^(double progress, NSError *e, BOOL *s, NSDictionary *d)  {
    NSLog(@"Progress: %g", progress);
    dispatch_async(dispatch_get_main_queue(), ^{
      self.infoText.text = [NSString stringWithFormat:@"Progress: %g", progress];
    });
  };
  self.lastRequestID = [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options
      resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix,
                      NSDictionary * _Nullable info) {
        NSLog(@"Setting currentAsset with avasset: %@, info: %@", asset, info);
        dispatch_async(dispatch_get_main_queue(), ^{
          self.infoText.text = [NSString stringWithFormat:@"Setting currentAsset with avasset: %@, info: %@", asset, info];
        });

        if (!asset) {
          NSLog(@"asset fetching failed");
          return;
        }

        self.assets = [self.assets arrayByAddingObject:asset];
        self.lastRequestID = -1;
      }];
}

- (IBAction)shuffleTapped:(id)sender {
  NSMutableArray *mutableAssets = [self.assets mutableCopy];
  NSUInteger count = [mutableAssets count];
  if (count <= 1) return;
  for (NSUInteger i = 0; i < count - 1; ++i) {
    NSInteger remainingCount = count - i;
    NSInteger exchangeIndex = i + arc4random_uniform((u_int32_t )remainingCount);
    [mutableAssets exchangeObjectAtIndex:i withObjectAtIndex:exchangeIndex];
  }

  self.assets = [mutableAssets copy];
}

- (IBAction)loadTapped:(id)sender {
  self.playerController.player = nil;
  AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:self.currentAsset];
  self.playerController.player = [AVPlayer playerWithPlayerItem:item];
  NSLog(@"Configured player: %@, status: %lu, error: %@", self.playerController.player, self.playerController.player.status, self.playerController.player.error);
  [self.playerController.player play];
  NSLog(@"Played player: %@, status: %lu, error: %@", self.playerController.player, self.playerController.player.status, self.playerController.player.error);
}

- (AVAsset *)currentAsset {
  AVMutableComposition *comp = [AVMutableComposition composition];
  AVMutableCompositionTrack *track = [comp addMutableTrackWithMediaType:AVMediaTypeVideo
                                                       preferredTrackID:1];

  if (self.apiSwitch.on) {
    NSMutableArray *segments = [NSMutableArray arrayWithCapacity:self.assets.count];
    CMTime currentTime = kCMTimeZero;
    for (AVAsset *asset in self.assets) {
      NSURL *assetURL = ((AVURLAsset *)asset).URL;
      AVCompositionTrackSegment *segment = [AVCompositionTrackSegment
                                            compositionTrackSegmentWithURL:assetURL
                                            trackID:asset.tracks.firstObject.trackID
                                            sourceTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration)
                                            targetTimeRange:CMTimeRangeMake(currentTime, asset.duration)];
      currentTime = CMTimeRangeGetEnd(segment.timeMapping.target);
      [segments addObject:segment];
    }

    track.segments = segments;
    NSLog(@"Segments using low level api: %@", comp.tracks.firstObject.segments);
  } else {
    for (AVAsset *asset in self.assets) {
      AVCompositionTrackSegment *lastSegment = track.segments.lastObject;
      CMTime start = lastSegment ? CMTimeRangeGetEnd(lastSegment.timeMapping.target) : kCMTimeZero;
      CMTimeRange timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
      BOOL success = [track insertTimeRange:timeRange ofTrack:asset.tracks.firstObject atTime:start
                                           error:nil];

      NSLog(@"Added TimeRange: %@ of asset: %@ succesfully: %d",
            [NSValue valueWithCMTimeRange:timeRange], asset, success);
    }

    NSLog(@"Segments using high level api: %@", comp.tracks.firstObject.segments);
  }




  return [comp copy];
}

- (PHFetchResult<PHAsset *> *)fetchVideoAssets {
  return [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeVideo
                                   options:[[PHFetchOptions alloc] init]];
}

- (void)setAssets:(NSMutableArray *)assets {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.assetsTextView.text = assets.count ? [(NSArray *)[assets valueForKey:@"URL"] description] : @"";
  });

  _assets = assets;
}

- (void)setVideoNumber:(NSUInteger)videoNumber {
  self.stepper.value = videoNumber;
  [self stepperChanged:self.stepper];
}

- (NSUInteger)videoNumber {
  return self.stepper.value;
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  NSLog(@"didReceiveMemoryWarning");
}


@end
