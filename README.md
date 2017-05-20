## 简介
iOS 10 中新增的通知服务扩展功能，在推送通知展示到界面之前提供开发者可以在后台对推送的内容进行**修改**。
通过这个修改主要可以实现以下的几个需求：
- 如果推送的内容加密的，可以在客户端进行解密。
- 可以下载图片，音乐，视频，实现多媒体推送的效果。
- 可以修改推送的内容，body ，titile ，subtitle 等。（这里可以用来实现一些定制化的需求，服务端统一推送，各自修改）
- 可以修改自己增加的 userinfo 的 dictionary。



说白了就是在收到苹果推送的时候，会触发你的
这是官方给出的注意点：

- 1.Include the mutable-content key with a value of 1.
一定要有 **mutable-content** 这个字段并且值为 1，不然是不会执行你的 extsion 的。
>我测试了改为0，或者不加这个字段并不会执行本地的修改

- 2.Include an alert dictionary with subkeys for the title and body of the alert.
 要有一个 alert 的 dictionary 包含 title 和 body 的键值。
 >如果没有 alert 的话，默认会当做一个 slient notification 

## Let's Start ！
这里主要分为两种实现方式：本地和远程。其实不管本地推送还是远程推送，对 app 本身其实是一致的。
主要讲一下远程的实现方式，因为这个的实际运用性更强一点，不过由于涉及到推送证书的缘故在 demo 中可能不好体现，最后我会给出本地推送的 demo 供大家测试。

#### 基础推送实现
这里我就不展开了，要运用修改推送的功能前提是你的 app 要已经有了推送能力。
主要以下几个注意点：
- 在 developer center 申请证书
- 在 application 中申请推送的权限
- 拿到 device Token 交给服务器的兄弟

这里推荐用 SmartPush 来本地测试本地推送，文章最后会介绍。
当服务端已经能愉快的给你推送的消息的时候，我们开始下一步。

#### 新建 extison

对 notification 的修改是作为一个 extison 的存在，并不是在你的 app 的 target 中增加一个 class 的事情，而是新建了一个 target。
- 选中 File -> New -> Target 
- 选择 Notification Service Extension
- 选择名字和相关信息
![](https://dn-mhke0kuv.qbox.me/e24ab0c37fee84f64f68.jpeg)

Xcode 会自动帮你配置好一切，然后会生成一个

**NotificationService** 的类
会帮你实现两个方法
- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler
> 收到推送时会触发的方法，给你一个 block 用来回调最终修改后的 Notification
- (void)serviceExtensionTimeWillExpire 
> 这个是这次 Service 运行时间到期时候的给你最后的通知（基础 后台拉取服务，通常的时间上限是 **30s**），相当是最后通牒，若你上面的下载操作还没完成，系统会最后询问你一次是不是要对内容修改，这里是你超时情况下最后的处理机会。

#### 代码实现

这里就直接贴代码吧，其实内容很简单，具体的流程会在注释中说明：
这里用了简单的一个 DownloadTask 来实现下载，其实如果是大文件或者多资源的话可以好好利用这个 30 秒进行下载。
```
#import "NotificationService.h"

@interface NotificationService ()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;
@property (nonatomic,strong) NSURLSessionDownloadTask *downLoadTask;//下载的task 用于取消

@end

@implementation NotificationService

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler {

    self.contentHandler = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];
    
    // Modify the notification content here...
    // self.bestAttemptContent.title = [NSString stringWithFormat:@"%@ [modified]", self.bestAttemptContent.title];
    
    //以上代码均有系统自动生成
    
    //获取下载的资源地址 这里和服务端约定好即可
    NSString *url = request.content.userInfo[@"attach"];
    NSURL *nsurl = [NSURL URLWithString:url];
    
    //开始下载
    self.downLoadTask = [[NSURLSession sharedSession] downloadTaskWithURL:nsurl completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        if (!error) {
        
        //将下载后的文件进行 移动到沙盒 切记这里的文件要及时清理    
            NSString *path = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:response.suggestedFilename];
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:nil];
            
        //为 Notification 增加 attachment
            UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"attachment" URL:[NSURL fileURLWithPath:path] options:nil error:nil];
            
            
            self.bestAttemptContent.attachments = @[attachment];
        }
        
        //不管成功失败 返回结果
        self.contentHandler(self.bestAttemptContent);
        
    }];
    
    [self.downLoadTask resume];
}

- (void)serviceExtensionTimeWillExpire {
    // Called just before the extension will be terminated by the system.
    // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
    NSLog(@"cancel ");
    //取消下载
    [self.downLoadTask cancel];
    self.contentHandler(self.bestAttemptContent);
}

@end

```

#### Debug

我自己测试的时候，发现直接运行时没法 debug ，根本进不了 service 的断点，研究了一下才发现了他的 debug 方式。

首先选中目标 service 的 target，**强调一下是 service 的 target**
![](https://dn-mhke0kuv.qbox.me/71f172b90822eda855b3.jpeg)
然后 build ，XCode 会提示让你选择对应的应用
![](https://dn-mhke0kuv.qbox.me/e115e2eca3bf81beb716.png)

然后就退到后台进行推送，这时候就能进到这个断点中了。

这里要强烈介绍一下这个 Mac 端的工具 ！！！炒鸡好用！！
Push 的工具推荐用 SmartPush 一个开源的 Mac 端push工具
https://github.com/shaojiankui/SmartPush
这个东西是神器！从此不用在和后端纠结证书的问题，我自己测试发送消息没问题之后就可以交给后台了，我的锅？不存在的！

![](https://dn-mhke0kuv.qbox.me/59cdb363d2c59e1160cc.png)


## Fire！

下面是我所测试的各种类型的效果图和对应的 payload 大家可以参考一下

图片推送
```
{
    "aps": {
        "alert": {
            "body": "多媒体推送", 
            "title": "我是图片", 
            "subtitle": "子标题"
        }, 
        "badge": 6, 
        "sound": "default", 
        "category": "Helllo", 
        "mutable-content": 1
    }, 
    "attach": "https://raw.githubusercontent.com/Danny1451/BlogPic/master/face/8.jpg"
}

```
效果大概是这样
![](https://dn-mhke0kuv.qbox.me/c81511171e98abf179b0.PNG)
点击之后是这样 一个耿直的微笑
![](https://dn-mhke0kuv.qbox.me/b9e485e4b27d4bd5337b.PNG)

mp3 文件
```
{
    "aps": {
        "alert": {
            "body": "多媒体推送", 
            "title": "我是音乐", 
            "subtitle": "子标题"
        }, 
        "badge": 6, 
        "sound": "default", 
        "category": "Helllo", 
        "mutable-content": 1
    }, 
    "attach": "https://raw.githubusercontent.com/Danny1451/BlogPic/master/pushtest/a.mp3"
}
```

![](https://dn-mhke0kuv.qbox.me/4b27748759e0721744be.PNG)

点击之后是这样：

![](https://dn-mhke0kuv.qbox.me/fb318f3ac1a4348e9356.PNG)
MP4 文件
```
{
    "aps": {
        "alert": {
            "body": "多媒体推送", 
            "title": "我是视频", 
            "subtitle": "子标题"
        }, 
        "badge": 6, 
        "sound": "default", 
        "category": "Helllo", 
        "mutable-content": 1
    }, 
    "attach": "https://raw.githubusercontent.com/Danny1451/BlogPic/master/pushtest/video.mp4"
}
```
点击之前就和音乐消息是一样的
之后是这样的

![](https://dn-mhke0kuv.qbox.me/0898087db244a1054a66.PNG)


## 最后

#### 注意点

- 注意文件下载的位置的存储管理，及时的清空。
- 注意如果要用第三方的库的话，extison 要单独引用和编译一份，因为和 app 一样他们其实是独立进程的。
- 注意户的网络情况，进行判断是否要下载资源，不然用户的流量就给你这么咔咔咔全耗完了。
