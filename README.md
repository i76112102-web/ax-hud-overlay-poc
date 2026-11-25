# ax-hud-overlay-poc

免越狱跨 App 悬浮窗的三种实现路径，从 AX Pro Max 1.5.3（`com.apple.music` / `Tips.app`，arm64e，cryptid=0）逆向还原后重写的最小可编译版本。

CI 直接产出**未签名 IPA**，下载后自签即可装到非越狱设备。

---

## 一、产物

| IPA | Bundle ID | 用途 | 免越狱可用 |
|---|---|---|---|
| `PiPOverlay.ipa` | `local.poc.pipoverlay` | 画中画浮窗：拉起目标 App 后 HUD 仍显示在它界面上 | ✅ 唯一官方跨 App 路径 |
| `HUDKeepAlive.ipa` | `local.poc.hudkeepalive` | 最高层 window + 静音音频保活 + 私有 UITouch 投递 | 仅覆盖本进程（对应样本容器化方案） |
| `ScreenShield.ipa` | `local.poc.screenshield` | 复现样本的防截屏护盾（secure text entry） | ✅ 装完截图即黑 |

下载地址二选一：

- **Releases**：`https://github.com/<owner>/<repo>/releases` —— 手动触发或打 tag 时自动发布
- **Actions → 对应 run → Artifacts → `ipa-unsigned-<n>`**

每个包都带 `SHA256SUMS.txt` 和 `build-info.txt`（Xcode 版本、SDK、clang 版本、UTC 时间戳）。

---

## 二、装机（未签名 IPA 必须自签）

### 方式 A：Sideloadly（Windows / macOS）

1. 装 iTunes（Windows 需 Apple 驱动）+ Sideloadly
2. IPA 拖进 Sideloadly，填 Apple ID
3. `Start` → 设备上 `设置 → 通用 → VPN与设备管理` 信任开发者证书
4. iOS 17+ 需先开「开发者模式」：`设置 → 隐私与安全性 → 开发者模式`

免费 Apple ID 签名有效期 7 天，过期重签。

### 方式 B：esign / AltStore

esign 导入 IPA → 选已导入的证书 → 签名 → 安装。企业证书或已购开发者证书可长期有效。

### 方式 C：已有 p12 时用命令行

```bash
unzip PiPOverlay.ipa -d out
codesign -f -s "iPhone Developer: Your Name (TEAMID)" \
  --entitlements ent.plist out/Payload/PiPOverlay.app
# ent.plist 至少要有 get-task-allow=true 与 application-identifier
```

---

## 三、PiPOverlay 验证清单

1. 启动 App，界面显示「拉起目标 App 后 HUD 仍浮在它上面」
2. 点按钮 → 顶部出现系统画中画小窗，画面是自绘 HUD（`tick` 在涨）
3. 约 1.2s 后自动拉起 `music://`
4. 目标 App 全屏在前，**画中画小窗仍浮在它上面**
5. 拖动 / 缩放 / 关闭都是系统原生行为

预期观察点：

| 现象 | 说明 |
|---|---|
| 小窗里 `tick` 继续增长 | 后台音频保活生效，进程没被挂起 |
| 小窗拖到屏幕边缘自动吸附隐藏 | 系统 PiP 行为，证明不是自绘浮层 |
| 目标 App 切到别的 App 后小窗还在 | PiP 由 SpringBoard 持有，不依赖本进程前台 |

改拉起目标：`targets/PiPOverlay/AppDelegate.m` 顶部

```objc
static NSString *const kLaunchURLString = @"music://";
static BOOL const kAutoLaunchAfterPiP = YES;
```

新 scheme 必须同时加进 `targets/PiPOverlay/Info.plist` 的 `LSApplicationQueriesSchemes`，否则 `canOpenURL:` 恒为 NO。

### 三个已踩过的坑（代码里已处理）

| 坑 | 原因 | 处理 |
|---|---|---|
| `isPictureInPicturePossible` 恒 NO | PiP 宿主 window 离屏 / `alpha=0` / `hidden=YES`，`AVSampleBufferDisplayLayer` 不上屏 | 宿主 window 放屏内、`windowLevel = Normal - 1`、`alpha = 0.02` |
| 切后台后立刻停帧 | `volume=0` 被系统判定「未输出音频」，不给后台时间 | 静音来自全零 PCM 采样，volume 保持默认 |
| 启动 PiP 直接失败 | 没有活跃的 playback 音频会话 | `startPiP` 里先 `setCategory:Playback` + `setActive:YES` |

---

## 四、HUDKeepAlive 验证清单

1. 启动 → 屏幕出现绿色浮球（`windowLevel = 10000000`）
2. 浮球可拖动；拖动时下层界面照常响应（`hitTest` 空白区返回 `nil` 实现穿透）
3. 点浮球 → 日志 `[demo] injected tap`，说明 `UIWindow sendEvent:` + 构造 UITouch 生效
4. 按 Home 键 → 进程不挂起（静音音频在播）

它只能覆盖自己进程的窗口。跨进程覆盖在免越狱下不可行 —— 样本之所以「看起来跨进程」，是因为目标 App 被加载进了它自己的进程。

---

## 五、ScreenShield 验证清单

1. 启动 → 橙色界面，中间写「SCREENSHOT ME」
2. 截图 → 相册里得到整屏深色，状态栏和 Home 条正常（说明截图通道没坏，是 App 层像素被剔除）
3. 点底部按钮关护盾 → 再截图，内容正常出现
4. 录屏 / AirPlay 镜像 → 额外叠一层渐变 + 毛玻璃遮罩（`UIScreen.isCaptured` 触发）

机制与样本 `Qm7Vx2Lp9R` 同构：全屏透明 `UITextField`（`secureTextEntry=YES`）成为 first responder，创建 `_UITextLayoutCanvasView`，系统合成器在捕获时剔除该 layer 子树。

---

## 六、本地复现构建

要求 macOS + Xcode Command Line Tools（不需要完整 Xcode 工程）。

```bash
bash scripts/build.sh                       # 三个全出
TARGETS="PiPOverlay" bash scripts/build.sh  # 只出一个
MIN_IOS=14.0 bash scripts/build.sh
```

不用 `.xcodeproj`、不用 xcodegen，`xcrun --sdk iphoneos clang` 直接交叉编译：

```
-target arm64-apple-ios15.0 -isysroot $SDK -fobjc-arc -O2
-framework UIKit -framework AVFoundation -framework AVKit ...
```

产物：

```
build/PiPOverlay.ipa
build/PiPOverlay/Payload/PiPOverlay.app/PiPOverlay
build/SHA256SUMS.txt
build/build-info.txt
```

构建脚本自带两道校验：`file` 必须是 `Mach-O 64-bit executable arm64`，`otool -l` 必须有 `LC_BUILD_VERSION`（确认 platform 是 iOS 而不是 macOS）。

---

## 七、代码结构

```
.
├── .github/workflows/build.yml   # macos-14，构建 + artifact + release
├── common/main.m                 # UIApplicationMain 入口（三 target 共用）
├── scripts/build.sh              # clang 交叉编译 + 打 IPA + 校验
└── targets/
    ├── PiPOverlay/               # PiPManager + AppDelegate
    ├── HUDKeepAlive/             # HUDWindow + AudioKeepAlive + TouchInjector
    └── ScreenShield/             # AXScreenShield + AppDelegate
```

---

## 八、与样本的对应关系

| 样本组件 | 证据 | 本仓库对应 |
|---|---|---|
| `AXHUDCoreAnimationRenderer` / `AXHUDReusableLayerPool` | 类名与 `menuWindowLevel` 常量 | `HUDWindow` 的 CG 自绘 |
| `Library/ax-hud-keepalive.wav` | 设备容器内实测存在 | `AudioKeepAlive` 内存生成静音 WAV |
| `_addTouch:forDelayedDelivery:` / `_touchesEvent` | 方法名 + selref | `TouchInjector` |
| `Qm7Vx2Lp9R`（UIWindow 子类） | 方法边界 0x10057BA94–0x10057F100 | `AXScreenShield` |
| 4 处 `setSecureTextEntry:YES` | `0x10057EFA0 / 0x100581C80 / 0x100581D94 / 0x100AE30FC` | 同一机制 |
| `AXZQBundleEnumerator` + `AXRuntimeSetOriginal` | 类名 + `SystemHook-vphone.dylib` 字符串 | 未实现（需容器化运行时） |

样本的「跨进程」不是注入，是**容器化**：把目标 App 的 Mach-O 手动 dyld 装载进自己进程，再叠同进程最高层 window。免越狱复现该效果只能走 PiP，本仓库 `PiPOverlay` 即是等价路径。

---

## 九、已知限制

- 未签名 IPA：必须自签，7 天（免费证书）或证书有效期（付费/企业）
- PiP 小窗尺寸由系统决定，不能自由拉伸成任意菜单形态
- `HUDKeepAlive` 的 UITouch 投递只在本进程有效；跨进程触摸需要 `IOHIDEventSystemClient` / `BKSHIDEvent`，属越狱范畴
- `ScreenShield` 依赖 `becomeFirstResponder` 成功；上屏前调用会失效，代码里已放在 `makeKeyAndVisible` 之后
