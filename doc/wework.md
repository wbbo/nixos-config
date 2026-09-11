# 企业微信 (Bottles/Wine) 适配记录

本机 (niri 26.04 + xwayland-satellite 0.8.2 + NVIDIA 595.71.05, 纯 Wayland) 上
通过 Bottles (Flatpak) 运行 Windows 版企业微信的完整适配过程、成功路径与已知限制。
适配日期 2026-09-10 ~ 09-12, 全部经实机验证。

---

## 结论速览

最终可用配置 = **caffe-10.0 runner + 禁 XWeb 硬件加速的策略注册表 + Maple Mono Hybrid 字体
+ wework-fix 守护服务 (清理故障 ARGB 子窗) + fcitx5 XIM 输入法**。

已知残余限制: 右键菜单/弹框首次打开时会闪 1~2 帧黑 (毫秒级自愈), 属上游
xwayland-satellite 在 NVIDIA 上的缺陷 (issue #502), 不影响功能。

---

## 一、最终配置 (bottle 名「企业微信」)

### Bottle 参数 (bottle.yml)

| 参数 | 值 | 原因 |
|------|----|------|
| Runner | **caffe-10.0** | 通用系 (Wine-tkg 基线), 对 CEF 商业应用友好 |
| wayland | false | caffe 构建不含 wine wayland driver, 走 XWayland |
| renderer / dxvk / sandbox | gdi / false / false | 非游戏应用; sandbox 会隔离网络 |

Runner 来源: Bottles 官方组件仓库 `https://proxy.usebottles.com/repo/components/runners/wine/`
(目录列表可直接 curl; 每个 yml 含下载 URL 与校验和)。**不要用 soda runner** ——
游戏向 Proton 补丁与企业微信的 CEF 冲突, 会导致崩溃循环 (TxBugReport 弹窗 + wine SEH 死锁)。

### Prefix 注册表 (wine)

```reg
; 1. 禁用 XWeb (内嵌浏览器) 硬件加速 —— 关键修复, 消除主窗/新窗口持续黑屏
[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\Chrome]
"HardwareAccelerationModeEnabled"=dword:00000000
; (同键位复制到 HKCU\SOFTWARE\Policies\Google\Chrome 与 \Chromium)

; 2. 中英文界面字体 → 自定义混排字体 (见下)
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Microsoft YaHei"="Maple Mono NF CN Hybrid"
"微软雅黑"="Maple Mono NF CN Hybrid"
... (共 18 项: 宋体/SimSun/黑体/Segoe UI/Arial/Tahoma/Calibri 等)
```

导入方式: 写好 UTF-16LE 的 .reg 放 prefix 内, 用
`flatpak run --command=bottles-cli com.usebottles.bottles run -b 企业微信 -e <prefix>/drive_c/windows/regedit.exe /S "C:\xxx.reg"`。
注意: regedit 删除注册表值 (`"Key"=-`) 会**静默失败**, 删除需停 wineserver 后直接编辑 user.reg。

### 字体: Maple Mono NF CN Hybrid

等宽字体 Maple Mono 在中文观感上「英文显粗、中文显细」(视觉密度差), 故做混排:
**英文用 Regular 字形 + 中文用 Medium 字形**。制作 (fonttools, glyf 表级替换):

```python
base = TTFont('MapleMono-NF-CN-Regular.ttf')   # 英文基准
med  = TTFont('MapleMono-NF-CN-Medium.ttf')    # 中文字形来源
# 对所有 CJK 码点 (U+2E80-FFEF 各区间, ~21000 字): base 的 glyf/hmtx 换为 med 的
# 字体名改 "Maple Mono NF CN Hybrid" 避免与原版冲突, 保存进 prefix Fonts/
```

字体文件源: 系统 nix store 的 `MapleMono-NF-CN-7.9` (复制 Regular/Medium/Bold 三档)。
注意: Noto CJK 的 VF ttc (CFF2) wine 枚举失败; fonttools CFF2 instancer 产物会引发
崩溃循环 —— 但静态 TTF 间的 glyf 表替换安全可用。

### 网络

Flatpak 沙箱内应用不吃宿主代理, 组件/依赖下载需注入:

```bash
flatpak override --user --env=http_proxy=http://127.0.0.1:7890 \
  --env=https_proxy=http://127.0.0.1:7890 --env=no_proxy=localhost,127.0.0.1 com.usebottles.bottles
```

### 输入法 (XIM)

wine 应用经 XIM 协议接 fcitx5: prefix 继承 `XMODIFIERS=@im=fcitx` (Bottles 的
Inherited_Environment_Variables 列表含 XMODIFIERS, 自动传入)。fcitx5 侧由
`modules/home/programs/fcitx5.nix` 的 systemd 服务常驻 + `fcitx5-xim-guard`
在 X server 重启后自动恢复 XIM 注册。**已在运行的企业微信实例在 XIM 失效后需重启**
(wine 不重试连接)。

---

## 二、问题与解决过程

### 2.1 主窗黑屏 / 只有图片没文字 (核心问题)

**现象**: 窗口黑或极暗, `xwd` (X 服务端) 抓取内容完全正常, `grim` (合成器) 全黑。

**根因链** (三层):
1. 企业微信的 CEF/XWeb 把 GPU 合成内容画在一个 **32 位 ARGB 子窗口** (Depth 32, 无名,
   常比父窗大), 在 NVIDIA + xwayland-satellite 下该子窗内容**读不到** (未初始化 GPU
   buffer), 空壳子窗盖住下层正常 GDI 绘制的 UI;
2. satellite 对运行中新建的窗口缓存首帧黑帧, 不重抓 → 双击菜单/弹框持续黑;
3. X server (satellite) 重启后 fcitx5 的 XIM 注册丢失 → 输入法失效。

**解决**:
- 策略注册表禁 XWeb 硬件加速 (见上) —— 让主窗内容回到 GDI 层;
- **wework-fix 守护服务** (`modules/home/programs/wework-fix.nix`): 2 秒轮询,
  自动 unmap「Depth 32 + 无名 + IsViewable + >10x10」的故障窗与 explorer 托盘窗,
  并写日志 (可审计); 实测菜单/弹框毫秒级自愈 (闪 1~2 帧黑);
- 输入法由 fcitx5 体系负责 (见上)。

**待上游根治**: xwayland-satellite 在 NVIDIA 上无法读取 32 位 ARGB 窗口内容。
已提交完整证据的 issue: **https://github.com/Supreeeme/xwayland-satellite/issues/502**
(含环境矩阵、xwd/grim 对照、Depth-32 判据、全部排除实验、源码分析)。上游修复后
wework-fix 守护可退役。

### 2.2 崩溃循环 (TxBugReport 弹窗)

**根因**: soda runner 的 Proton 游戏补丁与企业微信 CEF 不兼容 (wine SEH invalid frame
死锁)。**更换 runner 到 caffe 系解决**。换家族比在同家族换版本有效得多。

### 2.3 托盘白色图标横条

wine explorer.exe 的托盘窗 (159x19) 浮在桌面。**不可杀 explorer.exe 进程** (wine 会话
桌面进程, 杀掉连带企业微信退出)。双保险: niri `opacity 0.0` 规则 + 守护 unmap。

### 2.4 点击失效 (教训)

启动中途手动 unmap 了 wine 的 `Default IME` (1x1 输入法消息窗) 导致。**不要 unmap
1x1 窗口和 IME 窗口** —— 守护的 >10x10 尺寸阈值正是为此。

---

## 三、已排除的路线 (勿重蹈覆辙)

| 方向 | 结果 |
|------|------|
| `WINEDLLOVERRIDES=dwmapi=d` (禁 DWM) | ARGB 窗依旧创建 (非 DWM API 路径) |
| satellite `-glamor gl` / `es` / `none` | 三种后端全部测试: gl/es 与默认同为黑; none (-shm) 大窗完全不转发 + GL 错误 |
| satellite master 版 | 未修复 (0.8.2 同) |
| Wine 虚拟桌面 (注册表 `HKCU\Software\Wine\Explorer\Desktop`) | 生效但 satellite 完全无法转发虚拟桌面窗口, 比黑窗更糟; Bottles 自身 virtual_desktop 参数不生效 (Bottles bug) |
| 应用侧 `--disable-gpu*` 启动参数 | 主进程不转发给 CEF 子进程, 无效 |

---

## 四、排错工具箱

```bash
# 判断「黑」在哪一层: X 服务端内容 (真值) vs 合成器输出 (所见)
xwd -display :0 -id <窗口id> -out /tmp/f.xwd && magick /tmp/f.xwd /tmp/f.png   # X 端
grim /tmp/s.png                                                                 # 合成端
# 亮度量化 (对比两图同区域)
magick f.png -crop WxH+X+Y -colorspace Gray -format "%[fx:int(maxima*255)]" info:

# 窗口树与 Depth (找 32 位 ARGB 子窗)
xwininfo -display :0 -root -tree

# niri 窗口列表 (app_id/位置/尺寸)
niri msg --json windows

# 真实进程 comm (nix wrapper 带点前缀, 如 .fcitx5-wrapped —— pgrep -x fcitx5 永不匹配)
ps -eo pid,comm

# 服务状态
systemctl --user status wework-fix fcitx5-xim-guard fcitx5
DISPLAY=:0 xprop -root | grep XIM       # XIM 是否注册
```

## 五、关键操作备忘

- 启动企业微信: `flatpak run --command=bottles-cli com.usebottles.bottles run -b 企业微信 -e "<prefix>/drive_c/Program Files (x86)/WXWork/WXWork.exe"`
- **停机顺序**: 先停企业微信再动 satellite/X server (重启 X server 会杀死在跑的 wine 会话 —— wine 的 X 连接断开会 CriticalSection 死锁)
- `pkill -f 'WXWork.exe'` 与同命令行含 `WXWork.exe` 字面量的启动参数会**自杀** —— 分两条命令执行
- 强杀 (-9) 会损坏企业微信登录态 (需重新扫码); 改注册表后须杀 wineserver 才生效 (它常驻缓存)
