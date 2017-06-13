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

# iOS 10 来点不一样的推送 (2) - 语言提示

> 转自我的 Blog: [Danny's Dream]( http://danny-lau.com/2017/06/13/ios-10-notification-2/)


接着上篇[文章](https://juejin.im/post/591e9fe1a22b9d00585b2b60)，在一个交流群里有个小伙伴问，怎么实现支付宝类似收到钱之后的语音播放效果。

结合着之前对推送的研究，想到了两种实现方案：
- 1.在 notification 的 extension 中将收到的内容播放出来。
- 2.将文字转换成语音文件，保存在本地，然后替换为播放的提示音。

## 直接播放

#### AVFoundation
其实苹果有提供原生的文字转语音的功能，在 AVFoundation 框架中。简单的使用方法如下：

````
self.speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@“收到人民币1000000"];

AVSpeechSynthesisVoice *voiceType = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
utterance.voice = voiceType;
//设置语速
utterance.rate *= 0.5;
//设置音量
utterance.volume = 0.6;

[self.speechSynthesizer speakUtterance:utterance];

````
看上去很简单的样子，让我们赶紧放进 extension 中试一下。
在之前的基础上我们做一些修改，将播放操作封装成一个播放的方法。

````

- (void)readContent:(NSString*)str{
//AVSpeechUtterance: 可以假想成要说的一段话
AVSpeechUtterance * aVSpeechUtterance = [[AVSpeechUtterance alloc] initWithString:str];

aVSpeechUtterance.rate = AVSpeechUtteranceDefaultSpeechRate;

//AVSpeechSynthesisVoice: 可以假想成人的声音
aVSpeechUtterance.voice =[AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];

//发音
[self.aVSpeechSynthesizer speakUtterance:aVSpeechUtterance];

}

````
#### target 配置
在收到推送的时候，将推送的 body 读出来，想的还是美滋滋的。
把 demo 运行起来的时候，发现收到推送后并没有声音。
通过查阅资料，发现类似于这样的后台播放音乐，是需要一个 Background modes 的权限的，就是下面的第一个 Mode。【不过好像有人说，勾选了该权限可能会被拒】

![](https://dn-mhke0kuv.qbox.me/a22e6367c0a2844adeeb.png)

#### 音效不完整
然后我们再一次的尝试，这次可以播放出声音了，但是有个问题，就是声音播放到一半就停了，然后紧跟着的是推送的通知音。初步推测是播放其实也是在另一个线程中的进行的，当结束 extension 的操作弹出通知时，播放语音仍在进行中，会导致两个冲突，而系统通知的优先级更高，所以原来的语音会被拦截。
这一步考虑的解决方法是，在 extension 中做一个延迟的操作，首先想到的是用 GCD 。
````
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
dispatch_get_main_queue(), ^{

self.contentHandler(self.bestAttemptContent);

});
````
假设播放的语音是 5秒，在调用播放 5 秒之后，再触发处理完通知的回调，这样虽然是解决了上述的问题，但是似乎不够的优雅，无法控制如果语音更长的情况。

#### 自动结束

翻阅了文档，看看有没有可以收到播放完成的事件的地方。发现 AVSpeechSynthesizer 有一个 AVSpeechSynthesizerDelegate，将当前的 NotificationService 实现 AVSpeechSynthesizerDelegate，这样就能在下面的回调中结束播放成功时间，这样就能动态的控制通知展示的时间的。
````

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance;{

NSLog(@"阅读完毕");
self.contentHandler(self.bestAttemptContent);
}

````
这样就基本实现了我们想要的效果了！
由于推送的特殊性，可以实现后台唤醒，所以当 app 运行在后台，或者 app 被 kill 了，仍然可以唤醒并播放语言！😃

### 合成

考虑的是采用[科大讯飞](http://doc.xfyun.cn/msc_ios/302722)的语音合成 SDK，在 extension 中进行集成，然后转换成语音文件保存至本地，同时把推送的提示语音设置为该音频文件。
由于科大讯飞注册太麻烦了，就没尝试（跑。。）。不过感觉理论上应该可以实现该功能，主要有问题的地方可能就是转换之后的语言文件是否能作为提示音的问题了。


## 总结

基本的功能已经实现，最新的代码已经提交到原先的 [demo](https://github.com/Danny1451/PushTest.git) 中啦，但是需要注意的是 demo 不带证书，可以把相关代码拷到你自己的项目中去尝试，[演示视频](https://github.com/Danny1451/PushTest/blob/master/Demo.MOV)也传到 GitHub 中了。
(如果感到有用的加个✨吧 溜了 溜了）
