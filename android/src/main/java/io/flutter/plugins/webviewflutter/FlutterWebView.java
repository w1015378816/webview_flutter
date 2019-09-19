// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.webviewflutter;

import android.annotation.TargetApi;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.provider.MediaStore;
import android.view.View;
import android.webkit.WebStorage;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.platform.PlatformView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Collections;
import java.util.List;
import java.util.Map;

public class FlutterWebView implements PlatformView, MethodCallHandler {
  private static final String JS_CHANNEL_NAMES_FIELD = "javascriptChannelNames";
  private final WebView webView;
  private final MethodChannel methodChannel;
  private final FlutterWebViewClient flutterWebViewClient;
  private final Handler platformThreadHandler;
  private final Context context;

  @SuppressWarnings("unchecked")
  FlutterWebView(Context context, BinaryMessenger messenger, int id, Map<String, Object> params) {
    this.context = context;
    webView = new WebView(context);
    platformThreadHandler = new Handler(context.getMainLooper());
    // Allow local storage.
    webView.getSettings().setDomStorageEnabled(true);

    methodChannel = new MethodChannel(messenger, "plugins.flutter.io/webview_" + id);
    methodChannel.setMethodCallHandler(this);

    flutterWebViewClient = new FlutterWebViewClient(methodChannel);
    applySettings((Map<String, Object>) params.get("settings"));

    if (params.containsKey(JS_CHANNEL_NAMES_FIELD)) {
      registerJavaScriptChannelNames((List<String>) params.get(JS_CHANNEL_NAMES_FIELD));
    }

    if (params.containsKey("initialUrl")) {
      String url = (String) params.get("initialUrl");
      if (url.contains("://")) {
        webView.loadUrl(url);
      } else {
        webView.loadUrl("file:///android_asset/flutter_assets/" + url);
      }
    }
  }

  @Override
  public View getView() {
    return webView;
  }

  @Override
  public void onMethodCall(MethodCall methodCall, Result result) {
    switch (methodCall.method) {
      case "loadUrl":
        loadUrl(methodCall, result);
        break;
      case "loadAssetFile":
        loadAssetFile(methodCall, result);
        break;
      case "loadData":
        loadData(methodCall, result);
        break;
      case "saveWebImage":
        saveWebImage(methodCall, result);
        break;
      case "shareWebImage":
        shareWebImage(methodCall, result);
        break;
      case "updateSettings":
        updateSettings(methodCall, result);
        break;
      case "canGoBack":
        canGoBack(result);
        break;
      case "canGoForward":
        canGoForward(result);
        break;
      case "goBack":
        goBack(result);
        break;
      case "goForward":
        goForward(result);
        break;
      case "reload":
        reload(result);
        break;
      case "currentUrl":
        currentUrl(result);
        break;
      case "evaluateJavascript":
        evaluateJavaScript(methodCall, result);
        break;
      case "addJavascriptChannels":
        addJavaScriptChannels(methodCall, result);
        break;
      case "removeJavascriptChannels":
        removeJavaScriptChannels(methodCall, result);
        break;
      case "clearCache":
        clearCache(result);
        break;
      default:
        result.notImplemented();
    }
  }

  @SuppressWarnings("unchecked")
  private void loadUrl(MethodCall methodCall, Result result) {
    Map<String, Object> request = (Map<String, Object>) methodCall.arguments;
    String url = (String) request.get("url");
    Map<String, String> headers = (Map<String, String>) request.get("headers");
    if (headers == null) {
      headers = Collections.emptyMap();
    }
    webView.loadUrl(url, headers);
    result.success(null);
  }

  private void loadAssetFile(MethodCall methodCall, Result result) {
    String url = (String) methodCall.arguments;
    webView.loadUrl("file:///android_asset/flutter_assets/" + url);
    result.success(null);
  }

  private void loadData(MethodCall methodCall, Result result) {
    String baseUrl = methodCall.argument("baseUrl");
    String data = methodCall.argument("data");
    String mimeType = methodCall.argument("mimeType");
    String encoding = methodCall.argument("encoding");
    String historyUrl = methodCall.argument("historyUrl");
    webView.loadDataWithBaseURL(baseUrl, data, mimeType, encoding, historyUrl);
    result.success(null);
  }

  private void saveWebImage(MethodCall methodCall, Result result) {
    Bitmap bitmap = webToBitmap();
    String fileName = System.currentTimeMillis()+"";
    saveBmp2Gallery(context,bitmap, fileName);
    result.success(null);
  }

  /**
   * @param bmp 获取的bitmap数据
   * @param picName 自定义的图片名
   */
  public static void saveBmp2Gallery(Context context,Bitmap bmp, String picName) {
//    saveImageToGallery(bmp,picName);
    String fileName = null;
    //系统相册目录
    String galleryPath = Environment.getExternalStorageDirectory()
            + File.separator + Environment.DIRECTORY_DCIM
            + File.separator + "Camera" + File.separator;


    // 声明文件对象
    File file = null;
    // 声明输出流
    FileOutputStream outStream = null;
    try {
      // 如果有目标文件，直接获得文件对象，否则创建一个以filename为名称的文件
      file = new File(galleryPath, picName + ".jpg");
      // 获得文件相对路径
      fileName = file.toString();
      // 获得输出流，如果文件中有内容，追加内容
      outStream = new FileOutputStream(fileName);
      if (null != outStream) {
        bmp.compress(Bitmap.CompressFormat.JPEG, 90, outStream);
      }
    }catch (Exception e) {
      e.getStackTrace();
    } finally {
      try {
        if (outStream != null) {
          outStream.close();
        }
      } catch (IOException e) {
        e.printStackTrace();
      }
    }

    MediaStore.Images.Media.insertImage(context.getContentResolver(),bmp,fileName,null);
    Intent intent = new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE);
    Uri uri = Uri.fromFile(file);
    intent.setData(uri);
    context.sendBroadcast(intent);

    Toast.makeText(context,"图片保存成功", Toast.LENGTH_SHORT).show();

  }

  private Bitmap webToBitmap (){
    int height = (int) (webView.getContentHeight() * webView.getScale());
    int width = webView.getWidth();
    int pH = webView.getHeight();
    Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565);
    Canvas canvas = new Canvas(bitmap);
    int top = height;
    while (top > 0) {
      if (top < pH) {
        top = 0;
      } else {
        top -= pH;
      }
      canvas.save();
      canvas.clipRect(0, top, width, top + pH);
      webView.scrollTo(0, top);
      webView.draw(canvas);
      canvas.restore();
    }
    return bitmap;
  }

  private void shareWebImage(MethodCall methodCall, Result result) {
    Bitmap bitmap = webToBitmap();
    Uri uri = Uri.parse(MediaStore.Images.Media.insertImage(context.getContentResolver(), bitmap, null,null));
    Intent intent = new Intent();
    intent.setAction(Intent.ACTION_SEND);//设置分享行为
    intent.setType("image/*");//设置分享内容的类型
    intent.putExtra(Intent.EXTRA_STREAM, uri);
    intent = Intent.createChooser(intent, "分享");
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    context.startActivity(intent);
    result.success(null);
  }

  private void canGoBack(Result result) {
    result.success(webView.canGoBack());
  }

  private void canGoForward(Result result) {
    result.success(webView.canGoForward());
  }

  private void goBack(Result result) {
    if (webView.canGoBack()) {
      webView.goBack();
    }
    result.success(null);
  }

  private void goForward(Result result) {
    if (webView.canGoForward()) {
      webView.goForward();
    }
    result.success(null);
  }

  private void reload(Result result) {
    webView.reload();
    result.success(null);
  }

  private void currentUrl(Result result) {
    result.success(webView.getUrl());
  }

  @SuppressWarnings("unchecked")
  private void updateSettings(MethodCall methodCall, Result result) {
    applySettings((Map<String, Object>) methodCall.arguments);
    result.success(null);
  }

  @TargetApi(Build.VERSION_CODES.KITKAT)
  private void evaluateJavaScript(MethodCall methodCall, final Result result) {
    String jsString = (String) methodCall.arguments;
    if (jsString == null) {
      throw new UnsupportedOperationException("JavaScript string cannot be null");
    }
    webView.evaluateJavascript(
        jsString,
        new android.webkit.ValueCallback<String>() {
          @Override
          public void onReceiveValue(String value) {
            result.success(value);
          }
        });
  }

  @SuppressWarnings("unchecked")
  private void addJavaScriptChannels(MethodCall methodCall, Result result) {
    List<String> channelNames = (List<String>) methodCall.arguments;
    registerJavaScriptChannelNames(channelNames);
    result.success(null);
  }

  @SuppressWarnings("unchecked")
  private void removeJavaScriptChannels(MethodCall methodCall, Result result) {
    List<String> channelNames = (List<String>) methodCall.arguments;
    for (String channelName : channelNames) {
      webView.removeJavascriptInterface(channelName);
    }
    result.success(null);
  }

  private void clearCache(Result result) {
    webView.clearCache(true);
    WebStorage.getInstance().deleteAllData();
    result.success(null);
  }

  private void applySettings(Map<String, Object> settings) {
    for (String key : settings.keySet()) {
      switch (key) {
        case "jsMode":
          updateJsMode((Integer) settings.get(key));
          break;
        case "hasNavigationDelegate":
          final boolean hasNavigationDelegate = (boolean) settings.get(key);

          final WebViewClient webViewClient =
              flutterWebViewClient.createWebViewClient(hasNavigationDelegate);

          webView.setWebViewClient(webViewClient);
          break;
        default:
          throw new IllegalArgumentException("Unknown WebView setting: " + key);
      }
    }
  }

  private void updateJsMode(int mode) {
    switch (mode) {
      case 0: // disabled
        webView.getSettings().setJavaScriptEnabled(false);
        break;
      case 1: // unrestricted
        webView.getSettings().setJavaScriptEnabled(true);
        break;
      default:
        throw new IllegalArgumentException("Trying to set unknown JavaScript mode: " + mode);
    }
  }

  private void registerJavaScriptChannelNames(List<String> channelNames) {
    for (String channelName : channelNames) {
      webView.addJavascriptInterface(
          new JavaScriptChannel(methodChannel, channelName, platformThreadHandler), channelName);
    }
  }

  @Override
  public void dispose() {
    methodChannel.setMethodCallHandler(null);
  }
}
