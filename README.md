# CCClock - 控制中心时钟模块

一个标准的 iOS 控制中心模块（CCModule），在控制中心显示当前时间和日期。

**兼容 iOS 14.0 ~ iOS 17.x**，包括 16.5.1 半越狱环境。

## 与 CCTime 的区别

| | CCTime | CCClock（本项目） |
|---|---|---|
| 实现方式 | MobileSubstrate 注入 Hook | 标准 CCModule 控制中心模块 |
| 兼容性 | Hook 的类在 iOS 16 重构后可能失效 | 系统标准 API，全版本兼容 |
| 添加方式 | 自动显示（可能因坐标问题不可见） | 在控制中心"添加模块"中手动添加 |
| 稳定性 | 依赖 SpringBoard 内部类名 | 公开稳定的模块框架 |

## 功能特性

- 显示当前时间（HH:mm 格式）
- 显示当前日期（月日 + 星期）
- 每秒自动刷新
- 白色文字，适配深色/浅色控制中心背景
- 标准 2x2 模块大小

## 编译方法（无需 Mac，使用 GitHub Actions）

### 第一步：上传到 GitHub

1. 注册/登录 GitHub 账号
2. 点击右上角 **+** → **New repository**
3. 仓库名随意（如 `CCClockModule`），选择 **Public** 或 **Private**
4. 不要勾选 "Add a README file"
5. 点击 **Create repository**

6. 在本地解压本项目，然后在项目目录执行：
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/你的用户名/CCClockModule.git
   git push -u origin main
   ```

   （如果没有 git 环境，也可以在 GitHub 仓库页面点击 **Add file** → **Upload files**，手动上传所有文件和文件夹）

### 第二步：触发编译

1. 进入 GitHub 仓库页面
2. 点击顶部的 **Actions** 标签
3. 左侧选择 **Build Package**
4. 点击右侧 **Run workflow** → 再点 **Run workflow**
5. 等待约 3~5 分钟，状态变成绿色 ✓

### 第三步：下载 deb 包

1. 点击完成的 workflow run（绿色 ✓ 的那条）
2. 页面底部 **Artifacts** 区域，点击 **CCClockModule** 下载
3. 解压得到 `.deb` 安装包

## 安装方法

### 方法一：通过 Sileo 安装（推荐）

1. 将 deb 包传到手机（可用 AirDrop、微信文件传输、Filza 等）
2. 用 **Filza** 找到 deb 文件，点击选择 **Sileo** 打开
3. Sileo 中点击 **安装** → **确认**
4. 安装完成后 **Respring**

### 方法二：通过命令行安装

```bash
dpkg -i com.yourname.ccclockmodule_1.0.0_iphoneos-arm64.deb
killall SpringBoard
```

## 使用方法

1. 安装并 Respring 后，打开 **设置** → **控制中心**
2. 在 **更多控制** 列表中找到 **时钟**
3. 点击左边的 **+** 号添加到控制中心
4. 下拉控制中心即可看到时钟模块

## 自定义修改

### 修改模块大小

编辑 `Layout/Library/ControlCenter/Bundles/CCClockModule.bundle/Info.plist`：

```xml
<key>CCSModuleSize</key>
<dict>
    <key>Portrait</key>
    <dict>
        <key>Width</key>
        <integer>2</integer>  <!-- 改为 4 则占满一行 -->
        <key>Height</key>
        <integer>2</integer>
    </dict>
</dict>
```

### 修改文字颜色/大小

编辑 `Sources/CCClockContentViewController.m` 中的 `viewDidLoad` 方法：

```objc
// 时间文字颜色
self.timeLabel.textColor = [UIColor whiteColor];
// 时间字体大小
self.timeLabel.font = [UIFont systemFontOfSize:38 weight:UIFontWeightLight];
// 日期文字颜色
self.dateLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
```

### 修改时间/日期格式

编辑 `Sources/CCClockContentViewController.m` 中的 `updateTime` 方法：

```objc
// 时间格式：HH:mm（24小时制）、hh:mm a（12小时制）
[timeFormatter setDateFormat:@"HH:mm"];
// 日期格式
[dateFormatter setDateFormat:@"MM月dd日 EEEE"];
```

修改后重新提交到 GitHub，Actions 会自动重新编译。

## 项目结构

```
CCClockModule/
├── Makefile                          # Theos 构建配置
├── control                           # deb 包信息
├── CCClockModule-Info.plist          # 模块配置（Theos 自动识别）
├── .gitignore
├── .github/
│   └── workflows/
│       └── build.yml                 # GitHub Actions 在线编译（Rootless）
└── Sources/
    ├── CCClockModule.h               # 模块主类（实现 CCUIContentModule）
    ├── CCClockModule.m
    ├── CCClockContentViewController.h  # 内容视图控制器
    └── CCClockContentViewController.m
```

> GitHub Actions 默认编译 Rootless 版本（适配 Dopamine/Palera1n 等半越狱）。
> 如需 Rootful 版本，修改 `.github/workflows/build.yml`，移除 `THEOS_PACKAGE_SCHEME=rootless`。

## 常见问题

**Q: 安装后控制中心里找不到时钟模块？**
A: 确认已 Respring，然后去 设置 → 控制中心 → 更多控制 中手动添加。

**Q: 模块显示但文字看不清？**
A: 可修改源代码中的文字颜色，重新编译安装。

**Q: 想和 CCTime 一样自由调整位置？**
A: 标准 CCModule 的位置由系统控制中心布局管理，不能像 tweak 那样自由移动。如需自由定位，建议继续使用 CCTime 并排查其 Hook 失效问题。

## 许可证

MIT License
