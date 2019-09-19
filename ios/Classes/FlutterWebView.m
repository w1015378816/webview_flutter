// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FlutterWebView.h"
#import "FLTWKNavigationDelegate.h"
#import "JavaScriptChannelHandler.h"

@implementation FLTWebViewFactory {
    NSObject<FlutterPluginRegistrar>* _registrar;
    NSObject<FlutterBinaryMessenger>* _messenger;
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    self = [super init];
    if (self) {
        _registrar = registrar;
        _messenger = registrar.messenger;
    }
    return self;
}

- (NSObject<FlutterMessageCodec>*)createArgsCodec {
    return [FlutterStandardMessageCodec sharedInstance];
}

- (NSObject<FlutterPlatformView>*)createWithFrame:(CGRect)frame
                                   viewIdentifier:(int64_t)viewId
                                        arguments:(id _Nullable)args {
    FLTWebViewController* webviewController = [[FLTWebViewController alloc] initWithFrame:frame
                                                                           viewIdentifier:viewId
                                                                                arguments:args
                                                                                registrar:_registrar];
    return webviewController;
}

@end

@implementation FLTWebViewController {
    WKWebView* _webView;
    int64_t _viewId;
    FlutterMethodChannel* _channel;
    NSString* _currentUrl;
    // The set of registered JavaScript channel names.
    NSMutableSet* _javaScriptChannelNames;
    FLTWKNavigationDelegate* _navigationDelegate;
    NSObject<FlutterPluginRegistrar>* _registrar;
}

- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
                    registrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    if ([super init]) {
        _viewId = viewId;
        _registrar = registrar;
        
        NSString* channelName = [NSString stringWithFormat:@"plugins.flutter.io/webview_%lld", viewId];
        _channel = [FlutterMethodChannel methodChannelWithName:channelName
                                               binaryMessenger:registrar.messenger];
        _javaScriptChannelNames = [[NSMutableSet alloc] init];
        
        WKUserContentController* userContentController = [[WKUserContentController alloc] init];
        if ([args[@"javascriptChannelNames"] isKindOfClass:[NSArray class]]) {
            NSArray* javaScriptChannelNames = args[@"javascriptChannelNames"];
            [_javaScriptChannelNames addObjectsFromArray:javaScriptChannelNames];
            [self registerJavaScriptChannels:_javaScriptChannelNames controller:userContentController];
        }
        
        WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
        configuration.userContentController = userContentController;
        
        _webView = [[WKWebView alloc] initWithFrame:frame configuration:configuration];
        _navigationDelegate = [[FLTWKNavigationDelegate alloc] initWithChannel:_channel];
        _webView.navigationDelegate = _navigationDelegate;
        __weak __typeof__(self) weakSelf = self;
        [_channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
            [weakSelf onMethodCall:call result:result];
        }];
        NSDictionary<NSString*, id>* settings = args[@"settings"];
        [self applySettings:settings];
        
        NSString* initialUrl = args[@"initialUrl"];
        if ([initialUrl isKindOfClass:[NSString class]]) {
            if ([initialUrl rangeOfString:@"://"].location == NSNotFound) {
                [self loadAssetFile:initialUrl];
            } else {
                [self loadUrl:initialUrl];
            }
        }
    }
    return self;
}

- (UIView*)view {
    return _webView;
}

- (void)onMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([[call method] isEqualToString:@"updateSettings"]) {
        [self onUpdateSettings:call result:result];
    } else if ([[call method] isEqualToString:@"loadUrl"]) {
        [self onLoadUrl:call result:result];
    } else if ([[call method] isEqualToString:@"loadData"]) {
        [self onLoadData:call result:result];
    } else if ([[call method] isEqualToString:@"shareWebImage"]) {
        [self onShareImage:call result:result];
    } else if ([[call method] isEqualToString:@"saveWebImage"]) {
        [self onSaveImage:call result:result];
    } else if ([[call method] isEqualToString:@"loadAssetFile"]) {
        [self onLoadAssetFile:call result:result];
    } else if ([[call method] isEqualToString:@"canGoBack"]) {
        [self onCanGoBack:call result:result];
    } else if ([[call method] isEqualToString:@"canGoForward"]) {
        [self onCanGoForward:call result:result];
    } else if ([[call method] isEqualToString:@"goBack"]) {
        [self onGoBack:call result:result];
    } else if ([[call method] isEqualToString:@"goForward"]) {
        [self onGoForward:call result:result];
    } else if ([[call method] isEqualToString:@"reload"]) {
        [self onReload:call result:result];
    } else if ([[call method] isEqualToString:@"currentUrl"]) {
        [self onCurrentUrl:call result:result];
    } else if ([[call method] isEqualToString:@"evaluateJavascript"]) {
        [self onEvaluateJavaScript:call result:result];
    } else if ([[call method] isEqualToString:@"addJavascriptChannels"]) {
        [self onAddJavaScriptChannels:call result:result];
    } else if ([[call method] isEqualToString:@"removeJavascriptChannels"]) {
        [self onRemoveJavaScriptChannels:call result:result];
    } else if ([[call method] isEqualToString:@"clearCache"]) {
        [self clearCache:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)onUpdateSettings:(FlutterMethodCall*)call result:(FlutterResult)result {
    [self applySettings:[call arguments]];
    result(nil);
}

- (void)onLoadUrl:(FlutterMethodCall*)call result:(FlutterResult)result {
    if (![self loadRequest:[call arguments]]) {
        result([FlutterError
                errorWithCode:@"loadUrl_failed"
                message:@"Failed parsing the URL"
                details:[NSString stringWithFormat:@"Request was: '%@'", [call arguments]]]);
    } else {
        result(nil);
    }
}

- (void)onSaveImage:(FlutterMethodCall*)call result:(FlutterResult)result {
    // 制作了一个UIView的副本
    UIView *snapShotView = [_webView snapshotViewAfterScreenUpdates:YES];
    
    snapShotView.frame = CGRectMake(_webView.frame.origin.x, _webView.frame.origin.y, snapShotView.frame.size.width, snapShotView.frame.size.height);
    
    [_webView.superview addSubview:snapShotView];
    
    NSLog(@"分享图片到相册");
    // 获取当前UIView可滚动的内容长度
    CGPoint scrollOffset = _webView.scrollView.contentOffset;
    // 向上取整数 － 可滚动长度与UIView本身屏幕边界坐标相差倍数
    float maxIndex = ceilf(_webView.scrollView.contentSize.height/_webView.bounds.size.height);
    // 保持清晰度
    UIGraphicsBeginImageContextWithOptions(_webView.scrollView.contentSize, true, 0);
    
    //NSLog(@"--index--%d", (int)maxIndex);
    // 滚动截图
    [self ZTContentScroll:_webView PageDraw:0 maxIndex:(int)maxIndex drawCallback:^{
        UIImage *capturedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        // 恢复原UIView
        [self->_webView.scrollView setContentOffset:scrollOffset animated:NO];
        UIImageWriteToSavedPhotosAlbum(capturedImage, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
        [snapShotView removeFromSuperview];
        //
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                       message:@"保存图片成功."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction * action) {}];
        [alert addAction:cancelAction];
        [[self viewController:self->_webView] presentViewController:alert animated:YES completion:nil];
        result(nil);
    }];
}
#pragma mark -- <保存到相册>
-(void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    NSString *msg = nil ;
    if(error){
        msg = @"保存图片失败" ;
    }else{
        msg = @"保存图片成功" ;
    }
}
- (void)onShareImage:(FlutterMethodCall*)call result:(FlutterResult)result {
    
    NSLog(@"分享图片开始");
    //制作了一个UIView的副本
    UIView *snapShotView = [_webView snapshotViewAfterScreenUpdates:YES];
    snapShotView.frame = CGRectMake(_webView.frame.origin.x, _webView.frame.origin.y, snapShotView.frame.size.width, snapShotView.frame.size.height);
    [_webView.superview addSubview:snapShotView];
    
    // 获取当前UIView可滚动的内容长度
    CGPoint scrollOffset = _webView.scrollView.contentOffset;
    // 向上取整数 － 可滚动长度与UIView本身屏幕边界坐标相差倍数
    float maxIndex = ceilf(_webView.scrollView.contentSize.height/_webView.bounds.size.height);
    // 保持清晰度
    UIGraphicsBeginImageContextWithOptions(_webView.scrollView.contentSize, true, 0);
    //NSLog(@"--index--%d", (int)maxIndex);
    // 滚动截图
    [self ZTContentScroll:_webView PageDraw:0 maxIndex:(int)maxIndex drawCallback:^{
        UIImage *capturedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        // 恢复原UIView
        [snapShotView removeFromSuperview];
        [self->_webView.scrollView setContentOffset:scrollOffset animated:NO];
        [self shareWebImage:capturedImage];
    }];
    result(nil);
}
- (void)shareWebImage:(UIImage *)image{
    
    UIGraphicsBeginImageContext(CGSizeMake(image.size.width*0.98, image.size.height*0.98));
    [image drawInRect:CGRectMake(0,0,image.size.width*0.98,image.size.height*0.98)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImage *myImage = [UIImage imageWithData:UIImageJPEGRepresentation(newImage, 0.8)];
    
    NSArray *activityItems;
    NSString *textToShare1 = @"六棱镜长图分享";
    activityItems = @[textToShare1,myImage];
    
    UIActivityViewController *activityVC = [[UIActivityViewController alloc]initWithActivityItems:activityItems applicationActivities:nil];
    //去除一些不需要的图标选项
    activityVC.excludedActivityTypes = @[UIActivityTypePostToFacebook, UIActivityTypeAirDrop, UIActivityTypePostToWeibo, UIActivityTypePostToTencentWeibo];
    
    //成功失败的回调block
    UIActivityViewControllerCompletionWithItemsHandler myBlock = ^(UIActivityType __nullable activityType, BOOL completed, NSArray * __nullable returnedItems, NSError * __nullable activityError) {
        if (completed){
            NSLog(@"---------------completed");
        }else{
            NSLog(@"---------------canceled");
        }
    };
    activityVC.completionWithItemsHandler = myBlock;
    [[self viewController:_webView] presentViewController:activityVC animated:YES completion:nil];
}
- (UIViewController *)viewController:(UIView *)selView {
    for (UIView* next = [selView superview]; next; next = next.superview) {
        UIResponder *nextResponder = [next nextResponder];
        if ([nextResponder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)nextResponder;
        }
    }
    return nil;
}

// 滚动截图
- (void)ZTContentScroll:(WKWebView *)webView PageDraw:(int)index maxIndex:(int)maxIndex drawCallback:(void(^)(void) )drawCallback{
    [webView.scrollView setContentOffset:CGPointMake(0, (float)index * webView.frame.size.height)];
    CGRect splitFrame = CGRectMake(0, (float)index * webView.frame.size.height, webView.bounds.size.width, webView.bounds.size.height);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [webView drawViewHierarchyInRect:splitFrame afterScreenUpdates:YES];
        if(index < maxIndex){
            [self ZTContentScroll:webView PageDraw: index + 1 maxIndex:maxIndex drawCallback:drawCallback];
        }else{
            drawCallback();
        }
    });
}

- (void)onLoadData:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSDictionary * dic = [call arguments];
    NSString *data = dic[@"data"];
    //NSString *encoding = dic[@"encoding"];
    //NSString *mimeType = dic[@"mimeType"];
    NSString *urlStr = dic[@"baseUrl"];
    if([urlStr isKindOfClass:[NSNull class]]){
        [_webView loadHTMLString:data baseURL:nil];
    }else{
        [_webView loadHTMLString:data baseURL:[NSURL URLWithString:urlStr]];
    }
    
    /*if (![self loadRequest:[call arguments]]) {
     result([FlutterError
     errorWithCode:@"loadUrl_failed"
     message:@"Failed parsing the URL"
     details:[NSString stringWithFormat:@"Request was: '%@'", [call arguments]]]);
     } else {
     result(nil);
     }*/
    result(nil);
}
/*
 - (void)onLoadData:(FlutterMethodCall*)call result:(FlutterResult)result {
 NSDictionary * dic = [call arguments];
 NSString *data = dic[@"data"];
 NSString *encoding = dic[@"encoding"];
 NSString *mimeType = dic[@"mimeType"];
 NSString *urlStr = dic[@"baseUrl"];
 if([urlStr isKindOfClass:[NSNull class]]){
 [_webView loadHTMLString:data baseURL:nil];
 }else{
 [_webView loadHTMLString:data baseURL:[NSURL URLWithString:urlStr]];
 }
 result(nil);
 }*/

- (void)onLoadAssetFile:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString* url = [call arguments];
    if (![self loadAssetFile:url]) {
        result([FlutterError errorWithCode:@"loadAssetFile_failed"
                                   message:@"Failed parsing the URL"
                                   details:[NSString stringWithFormat:@"URL was: '%@'", url]]);
    } else {
        result(nil);
    }
}

- (void)onCanGoBack:(FlutterMethodCall*)call result:(FlutterResult)result {
    BOOL canGoBack = [_webView canGoBack];
    result([NSNumber numberWithBool:canGoBack]);
}

- (void)onCanGoForward:(FlutterMethodCall*)call result:(FlutterResult)result {
    BOOL canGoForward = [_webView canGoForward];
    result([NSNumber numberWithBool:canGoForward]);
}

- (void)onGoBack:(FlutterMethodCall*)call result:(FlutterResult)result {
    [_webView goBack];
    result(nil);
}

- (void)onGoForward:(FlutterMethodCall*)call result:(FlutterResult)result {
    [_webView goForward];
    result(nil);
}

- (void)onReload:(FlutterMethodCall*)call result:(FlutterResult)result {
    [_webView reload];
    result(nil);
}

- (void)onCurrentUrl:(FlutterMethodCall*)call result:(FlutterResult)result {
    _currentUrl = [[_webView URL] absoluteString];
    result(_currentUrl);
}

- (void)onEvaluateJavaScript:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString* jsString = [call arguments];
    if (!jsString) {
        result([FlutterError errorWithCode:@"evaluateJavaScript_failed"
                                   message:@"JavaScript String cannot be null"
                                   details:nil]);
        return;
    }
    [_webView evaluateJavaScript:jsString
               completionHandler:^(_Nullable id evaluateResult, NSError* _Nullable error) {
                   if (error) {
                       result([FlutterError
                               errorWithCode:@"evaluateJavaScript_failed"
                               message:@"Failed evaluating JavaScript"
                               details:[NSString stringWithFormat:@"JavaScript string was: '%@'\n%@",
                                        jsString, error]]);
                   } else {
                       result([NSString stringWithFormat:@"%@", evaluateResult]);
                   }
               }];
}

- (void)onAddJavaScriptChannels:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSArray* channelNames = [call arguments];
    NSSet* channelNamesSet = [[NSSet alloc] initWithArray:channelNames];
    [_javaScriptChannelNames addObjectsFromArray:channelNames];
    [self registerJavaScriptChannels:channelNamesSet
                          controller:_webView.configuration.userContentController];
    result(nil);
}

- (void)onRemoveJavaScriptChannels:(FlutterMethodCall*)call result:(FlutterResult)result {
    // WkWebView does not support removing a single user script, so instead we remove all
    // user scripts, all message handlers. And re-register channels that shouldn't be removed.
    [_webView.configuration.userContentController removeAllUserScripts];
    for (NSString* channelName in _javaScriptChannelNames) {
        [_webView.configuration.userContentController removeScriptMessageHandlerForName:channelName];
    }
    
    NSArray* channelNamesToRemove = [call arguments];
    for (NSString* channelName in channelNamesToRemove) {
        [_javaScriptChannelNames removeObject:channelName];
    }
    
    [self registerJavaScriptChannels:_javaScriptChannelNames
                          controller:_webView.configuration.userContentController];
    result(nil);
}

- (void)clearCache:(FlutterResult)result {
    if (@available(iOS 9.0, *)) {
        NSSet* cacheDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
        WKWebsiteDataStore* dataStore = [WKWebsiteDataStore defaultDataStore];
        NSDate* dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
        [dataStore removeDataOfTypes:cacheDataTypes
                       modifiedSince:dateFrom
                   completionHandler:^{
                       result(nil);
                   }];
    } else {
        // support for iOS8 tracked in https://github.com/flutter/flutter/issues/27624.
        NSLog(@"Clearing cache is not supported for Flutter WebViews prior to iOS 9.");
    }
}

- (void)applySettings:(NSDictionary<NSString*, id>*)settings {
    for (NSString* key in settings) {
        if ([key isEqualToString:@"jsMode"]) {
            NSNumber* mode = settings[key];
            [self updateJsMode:mode];
        } else if ([key isEqualToString:@"hasNavigationDelegate"]) {
            NSNumber* hasDartNavigationDelegate = settings[key];
            _navigationDelegate.hasDartNavigationDelegate = [hasDartNavigationDelegate boolValue];
        } else {
            NSLog(@"webview_flutter: unknown setting key: %@", key);
        }
    }
}

- (void)updateJsMode:(NSNumber*)mode {
    WKPreferences* preferences = [[_webView configuration] preferences];
    switch ([mode integerValue]) {
        case 0:  // disabled
            [preferences setJavaScriptEnabled:NO];
            break;
        case 1:  // unrestricted
            [preferences setJavaScriptEnabled:YES];
            break;
        default:
            NSLog(@"webview_flutter: unknown JavaScript mode: %@", mode);
    }
}

- (bool)loadRequest:(NSDictionary<NSString*, id>*)request {
    if (!request) {
        return false;
    }
    
    NSString* url = request[@"url"];
    if ([url isKindOfClass:[NSString class]]) {
        id headers = request[@"headers"];
        if ([headers isKindOfClass:[NSDictionary class]]) {
            return [self loadUrl:url withHeaders:headers];
        } else {
            return [self loadUrl:url];
        }
    }
    
    return false;
}

- (bool)loadUrl:(NSString*)url {
    return [self loadUrl:url withHeaders:[NSMutableDictionary dictionary]];
}

- (bool)loadUrl:(NSString*)url withHeaders:(NSDictionary<NSString*, NSString*>*)headers {
    NSURL* nsUrl = [NSURL URLWithString:url];
    if (!nsUrl) {
        return false;
    }
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:nsUrl];
    [request setAllHTTPHeaderFields:headers];
    [_webView loadRequest:request];
    return true;
}

- (bool)loadAssetFile:(NSString*)url {
    NSString* key = [_registrar lookupKeyForAsset:url];
    NSURL* nsUrl = [[NSBundle mainBundle] URLForResource:key withExtension:nil];
    if (!nsUrl) {
        return false;
    }
    if (@available(iOS 9.0, *)) {
        [_webView loadFileURL:nsUrl allowingReadAccessToURL:[NSURL URLWithString:@"file:///"]];
    } else {
        return false;
    }
    return true;
}

- (void)registerJavaScriptChannels:(NSSet*)channelNames
                        controller:(WKUserContentController*)userContentController {
    for (NSString* channelName in channelNames) {
        FLTJavaScriptChannel* channel =
        [[FLTJavaScriptChannel alloc] initWithMethodChannel:_channel
                                      javaScriptChannelName:channelName];
        [userContentController addScriptMessageHandler:channel name:channelName];
        NSString* wrapperSource = [NSString
                                   stringWithFormat:@"window.%@ = webkit.messageHandlers.%@;", channelName, channelName];
        WKUserScript* wrapperScript =
        [[WKUserScript alloc] initWithSource:wrapperSource
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:NO];
        [userContentController addUserScript:wrapperScript];
    }
}

@end
