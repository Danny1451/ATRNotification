//
//  ViewController.m
//  PustTest
//
//  Created by 刘旦 on 20/05/2017.
//  Copyright © 2017 danny. All rights reserved.
//

#import "ViewController.h"
#import <UserNotifications/UserNotifications.h>
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)clickFire:(id)sender {
    
    
    
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Opps!";
    content.body = @"Surprise ! Mother Fucker ! 😎";
    content.sound = [UNNotificationSound defaultSound];
    
    NSString *imageUrl = @"https://raw.githubusercontent.com/Danny1451/BlogPic/master/face/8.jpg";
    
    
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:[NSURL URLWithString:imageUrl]  completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        if (!error) {
            
            //从临时目录移动到沙盒
            NSString *path = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:response.suggestedFilename];
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:nil];
            
            //增加 attach
            UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"attachment" URL:[NSURL fileURLWithPath:path] options:nil error:nil];
            
            content.attachments = @[attachment];
            
            //延时触发
            UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:10 repeats:NO];
            NSString *identifier = @"media";
            UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
            [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
                //发送成功
                if (!error) {
                    NSLog(@"send successfully !");
                }
                
            }];
        
        }
        
    }];

    [task resume];
    }


@end
