# Flutter Agent Interview App

这是 `LLM Agent Interview Lab` 的 Flutter 移动端 App。

当前定位：

- 不使用后端。
- 不做 RAG 请求。
- 对话、用户画像、模型设置保存在本机。
- 未配置 API Key 时使用内置知识 Demo 回答。
- 配置 OpenAI-compatible API Key 后，App 直连 `/chat/completions`。

## 生成 Android / iOS 工程

本目录只提交 Flutter 业务代码和配置。安装 Flutter SDK 后，在本目录执行：

```bash
flutter create .
flutter pub get
```

## 运行

Android:

```bash
flutter run
```

iOS:

```bash
flutter run
```

iOS 需要 macOS 和 Xcode。

## 打包

Android APK:

```bash
flutter build apk --release
```

Android App Bundle:

```bash
flutter build appbundle --release
```

iOS:

```bash
flutter build ios --release
```

## 注意

前端直连模型会把 API Key 保存在设备本地，适合个人学习 MVP。公开给多人使用时，应增加后端代理。

