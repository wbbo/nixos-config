# 企业微信 (Bottles/Wine) 适配记录

本机 (niri 26.04 + xwayland-satellite 0.8.2 + NVIDIA 595.71.05, 纯 Wayland) 上
通过 Bottles (Flatpak) 运行 Windows 版企业微信的完整适配过程、成功路径与已知限制。
适配日期 2026-09-10 ~ 09-12, 全部经实机验证。

> **2026-09-17 更新**: 09-14 重装后 bottle 重建, 手工适配全部丢失 (runner 回落
> soda、策略注册表/字体清空) —— 印证了「适配落在 prefix 内部, 非声明式即失」。
> 现已全部固化进 `modules/home/programs/wework.nix` (适配服务 + ARGB 守护 +
> 启动器), 重建 bottle 后一条 rebuild 自动重放, 见文末「七、声明式适配」。
> 本文其余部分保留原始手工过程, 作为排查依据。

---

## 结论速览

最终可用配置 = **caffe-10.0 runner + 禁 XWeb 硬件加速的策略注册表 + 字体替换 (界面字体
→ Maple Mono NF CN) + wework-fix 守护服务 (清理故障 ARGB 子窗) + fcitx5 XIM 输入法**。

**2026-09-18 根治**: 真因已定位为 **niri 在 dmabuf 路径上丢失 ARGB buffer 的
alpha** (不是 satellite, 也不是应用), 通过给 Xwayland 加 `-shm` 绕过 —— 见 §8.9。
此后透明外框窗能正确透出下层, **黑窗与闪烁同时消失**, `wework-fix` 守护的 ARGB
部分已无必要 (托盘部分保留)。

---

## 一、最终配置 (bottle 名「Work」, 2026-09-17 前为「企业微信」)

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

; 2. 中英文界面字体 → 原版 Maple Mono NF CN (见下)
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Microsoft YaHei"="Maple Mono NF CN"
"微软雅黑"="Maple Mono NF CN"
... (共 18 项: 宋体/SimSun/黑体/Segoe UI/Arial/Tahoma/Calibri 等)
```

导入方式: 写好 UTF-16LE 的 .reg 放 prefix 内, 用
`flatpak run --command=bottles-cli com.usebottles.bottles run -b Work -e <prefix>/drive_c/windows/regedit.exe /S "C:\xxx.reg"`。
注意: regedit 删除注册表值 (`"Key"=-`) 会**静默失败**, 删除需停 wineserver 后直接编辑 user.reg。

### 字体替换: Microsoft YaHei 等 → Maple Mono NF CN

把 Windows 界面字体名 (雅黑/宋体/黑体/Segoe UI/Arial/Tahoma/Calibri 等 18 项) 统一
映射到 **原版 Maple Mono NF CN** (系统 nix store 的 `MapleMono-NF-CN-7.9`, 由
fonts.nix 装入宿主)。**不需要往 prefix 拷任何字体文件** —— wine 自动扫描宿主字体,
登记在 prefix 的 `[Software\Wine\Fonts\External Fonts]` (`Z:\run\host\fonts\*.ttf`),
替换名直接可解析。

> **已退役: Maple Mono NF CN Hybrid 混排 (2026-09-17 移除)**。曾因等宽字体「英文显粗、
> 中文显细」的视觉密度差, 自建混排字体 (英文 Regular 字形 + 中文 Medium 字形, fonttools
> glyf 表级替换, 字体名换 Hybrid 避免与原版冲突, 拷进 prefix Fonts/)。该方案已移除,
> 直接指向原版; 相关技术知识保留在下方「踩坑清单 · 显示/字体」—— CFF2/VF instancer 会
> 引发 wine 崩溃循环, 静态 TTF 间 glyf 表替换是安全的, 将来若需重建混排可循此路。

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

**根因链** (2026-09-17 实机取证更正 —— 原文此处描述的是**错的拓扑**, 见 §八):
1. 企业微信会创建**透明的 Depth-32 (ARGB) 顶层窗**当窗口外框/阴影 (`xwininfo` 实测
   `Parent window id` 是 **root**, 不是主窗的子窗)。它是 root 直接子窗 → satellite
   接管 → 在 niri 里成为**独立窗**叠在应用窗上; 其内容为「全透明 + 一圈白色圆角边」,
   却因 **alpha 未被尊重**而渲染成不透明黑, 整块盖住应用 → 黑窗;
2. 该窗每次创建都会黑一次, 由 wework-fix 守护即时 unmap (事件驱动, ~1ms);
3. X server (satellite) 重启后 fcitx5 的 XIM 注册丢失 → 输入法失效。

**解决**:
- 策略注册表禁 XWeb 硬件加速 (见上) —— 让主窗内容回到 GDI 层;
- **wework-fix 守护服务** (`modules/home/programs/wework.nix`, 09-17 前为 wework-fix.nix):
  事件驱动监听 root 的 SubstructureNotify, 收到 MapNotify 即判窗 unmap;
  判据「无名 + wxwork + Depth 32 + IsViewable + >10x10」, 另有 explorer 托盘窗;
  全程写日志 (可审计)。实测延迟 ~1ms (见 §8.8);
- 输入法由 fcitx5 体系负责 (见上)。

**待上游根治**: 黑窗的根因**不在 xwayland-satellite**(它是纯 buffer 转发, 没有
像素路径), 也不在"应用没画出来" —— 是一个**设计上透明的 32 位 ARGB 顶层窗被当作
不透明黑渲染**, 完整取证见 **§八 根因定位**。上游修复后 wework-fix 守护可退役。

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
| satellite `-glamor gl` / `es` | 与默认同为黑 (都走 dmabuf, 同样丢 alpha) |
| ~~satellite `-glamor none` (-shm)~~ | ~~大窗完全不转发 + GL 错误~~ → **2026-09-18 更正: 这条记录是误判, `-glamor none` 正是最终方案 (§8.9)**。当时那条 `GL_INVALID_VALUE` 其实来自 **niri 的渲染器**, 与 shm 能否转发窗口无关; 本次实测 `-glamor none` 下 1897x2130 的大窗转发/显示都正常。教训: 别把 A 层的错误日志当成 B 层不可用的证据 |
| satellite master 版 | 未修复 (0.8.2 同) |
| Wine 虚拟桌面 (注册表 `HKCU\Software\Wine\Explorer\Desktop`) | 生效但 satellite 完全无法转发虚拟桌面窗口, 比黑窗更糟; Bottles 自身 virtual_desktop 参数不生效 (Bottles bug) |
| 应用侧 `--disable-gpu*` 启动参数 | 主进程不转发给 CEF 子进程, 无效 |
| **bottle 内跑 Windows 版 ToDesk** (09-17 实测) | 崩溃, **换 runner 家族同样失败** (对照实验): caffe-10.0 报 `Unhandled page fault` (读 0x20 空指针, 两次复现); soda-11.0-10 报 `unimplemented function ADVAPI32.dll.AuditSetSystemPolicy, aborting` —— 后者揭示根因: ToDesk 调用 wine **未实现**的 Windows 审计策略 API (远控软件的系统级安全审计), 两个家族都没有实现, 与 runner 选择无关。bottle 里的 ToDesk 留着无害 (不启动就不崩) |

---

## 四、踩坑清单 (操作层教训)

**进程操作**

- `pkill -9 -f 'X.exe'` 与**同命令行内**含该字面量的启动参数 = 自杀 (pkill 匹配到自身
  bash)。分两条命令执行; 模式写 `X[.]exe` 只能解决部分场景。
- **杀 explorer.exe = 杀整个 wine 会话** (它是桌面进程, 企业微信一起退出) —— 托盘窗
  只能窗口级 unmap。
- **强杀 (-9) 会损坏企业微信登录态** (需重新扫码); 改注册表后须杀 wineserver 才生效
  (它常驻缓存注册表)。
- nix wrapper 进程的 **comm 带点前缀** (`.fcitx5-wrapped` / `.xwayland-satel`) →
  `pgrep -x fcitx5` 永不匹配; 判活用 `systemctl --user is-active`。
- 企业微信**单实例**: 旧实例在跑时新实例静默退出 (表现为「启动失败」)。

**nix / systemd**

- `writeShellScript` **不注入** runtimeInputs 的 PATH (脚本内命令必须绝对路径);
  `writeShellApplication` 才注入。
- HM 生成的配置文件是 **store 只读链接**: `sed -i` 会把它替换成普通文件 (试验后须
  `rm` + `cp` + `chmod 444` 还原); 无地址 sed 会误伤全文件。
- HM 部署 unit 前须删除手动创建的同名 unit, 否则激活失败; flake 引用新文件须先
  `git add`。
- flatpak 沙箱内应用**不吃宿主代理**, 需 `flatpak override --user --env=...`。
- `writeShellApplication` 的 `bashOptions` **只认长选项名** —— 每项生成一行
  `set -o <name>`, 写短名 `[ "e" "u" "o" ]` 会生成非法的 `set -o e`, 三行 set 全部
  报错且**脚本照跑** (严格模式静默失效, 失去错误保护)。默认值
  `[ "errexit" "nounset" "pipefail" ]` 已等价 `set -euo pipefail`, 一般不用设。

**显示 / 字体**

- `place-within-backdrop` 是 **layer-rule 专用**属性, 放进 window-rule 会导致 niri
  **拒载整份配置并静默跑旧配置**。
- `xev -id` 只能收到窗口**已注册事件掩码**里的事件, 不能用它判断「事件未到达」。
- 窗口像素 diff 需要**无操作对照组** (点击动画/视频帧都会污染结果)。
- **CFF2 可变字体** (Noto CJK VF ttc) wine/freetype 枚举失败; fonttools 的 CFF2
  instancer 产物会引发 wine 崩溃循环; 但**静态 TTF 间的 glyf 表级替换**安全可用。
- Maple Mono CN 各字重的**中文字形是独立的** (实测 hash 不同);「英文比中文粗」是
  等宽字体拉丁/汉字的视觉密度差, 不是配置错误。
- **niri 锁屏时 `grim` 截到的是锁屏界面** (深色底 + 「请输入密码并按 Enter 键。」+
  天气/注销按钮), 不是桌面真实画面 —— 截图验证 GUI 前先查锁屏状态
  (`loginctl show-session 4 -p LockedHint`, 或 journalctl --user -u niri 找
  "locking/unlocking session")。09-17 曾把锁屏截图误读成 "TTY/黑屏", 白忙一轮。

**wine 行为**

- wine 10 的**虚拟桌面走注册表** (`HKCU\Software\Wine\Explorer\Desktop`), 命令行参数
  不变; `regedit /S` **删除**注册表值会静默失败 → 停 wineserver 后直接编辑 `user.reg`。
- 虚拟桌面模式下 satellite **完全无法转发窗口** (主窗 IsUnviewable), 比黑窗更糟 ——
  此路不通 (详见上节)。
- Bottles 自身的 `virtual_desktop` 参数不生效 (Bottles bug)。

**bottles-cli (09-17 补充, 声明式适配时实测)**

- `bottles-cli reg add` 报 `stdout decoding failed` 且**静默不写入** —— CLI 写注册表
  此路不通, 用 regedit 导 UTF-16LE .reg (见「一、最终配置」的导入方式)。
- `bottles-cli edit --runner` 会触发 **wineprefix 更新 (wineboot)**, 更新拉起的
  explorer 会执行企业微信的自启动键 (HKCU Run, 命令行带 `-min -autorun`) ——
  整个 wine 会话被企业微信挂住, edit **41 分钟不返回**; 且用户没主动启动却多出一个
  企业微信实例。对策: edit 之后必须 `bottles-cli stop -b` 收尾 (适配脚本已内置)。
- 换 runner 需先把 runner 包解到 `runners/<name>/{bin,lib,share}` (包内顶层目录
  strip 掉一层), 再 `edit --runner` —— 缺包时 edit **静默失败** (不报错也不切换)。
- 判断进程别用 `pgrep -f 'WXWork.exe'` —— 同命令行含该字面量时自匹配 (与下方
  pkill 自杀同源), 模式写 `WXWork[.]exe`。

---

## 五、排错工具箱

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
systemctl --user status wework-fix wework-adapt fcitx5-xim-guard fcitx5
DISPLAY=:0 xprop -root | grep XIM       # XIM 是否注册

# 适配服务日志 (自检了哪些项 / 补了哪些项)
journalctl --user -u wework-adapt --no-pager -n 20
```

## 六、关键操作备忘

- 启动企业微信: `flatpak run --command=bottles-cli com.usebottles.bottles run -b Work -e "<prefix>/drive_c/Program Files (x86)/WXWork/WXWork.exe"` (或启动器 Mod+Space 搜「企业微信」)
- **停机顺序**: 先停企业微信再动 satellite/X server (重启 X server 会杀死在跑的 wine 会话 —— wine 的 X 连接断开会 CriticalSection 死锁)
- `pkill -f 'WXWork.exe'` 与同命令行含 `WXWork.exe` 字面量的启动参数会**自杀** —— 分两条命令执行
- 强杀 (-9) 会损坏企业微信登录态 (需重新扫码); 改注册表后须杀 wineserver 才生效 (它常驻缓存)
- 重建 bottle 后无需手工重做适配: `systemctl --user start wework-adapt` (或等定时器) 自动补齐三项配置

## 七、声明式适配 (2026-09-17)

`modules/home/programs/wework.nix` — 单模块聚合三块内容:

| 组件 | 形式 | 职责 |
|------|------|------|
| `wework-adapt` 服务 + 30min 定时器 | oneshot, 幂等自检 | 补齐 runner / 策略注册表 / 字体替换 (§一 的三项, 已就绪即跳过) |
| `wework-fix` 服务 | X 事件驱动守护 (~1ms 响应) | unmap 故障 ARGB 外框窗 + explorer 托盘横条 (§2.1 的桌面侧兜底) |
| `wework-launch` + .desktop | 启动 wrapper | 启动器 (Mod+Space) 可搜可启动 |

配套文件 (同目录 `wework/`):

- `adapt.sh` — 适配脚本本体 (适配项: runner / 策略注册表 / 字体替换)。自检读 prefix 实际状态 (bottle.yml / user.reg) 而非
  "跑过没有", 手工改坏后 30 分钟内自动纠回。企业微信运行中时跳过本轮 (改 runner
  会打断会话), 由定时器在退出后重试。

**bottle 改名 (2026-09-17, 「企业微信」→「Work」)**: bottle 名即目录名, 但 bottle.yml
内的 External_Programs 路径与 Name/Path 字段以 **YAML unicode 转义** (`\u4F01...`) 存旧名,
grep 中文搜不到 —— 改名 = 停会话 + `mv` 目录 + 按转义模式 `sed` 替换 bottle.yml。
模块内引用 (adapt.sh 的 BOTTLE_NAME / wework-launch 的 -b / desktop Icon 路径) 同步改 Work。

**幂等验证过的路径** (2026-09-17 实测): 三项就位 → 全部跳过; 删掉策略注册表键
→ 下轮自动写回; 手工切回 soda runner → 下轮自动换回 caffe (前提 runner 包已在本地);
字体替换目标从 Hybrid 改为原版 → 下轮自动重导入并清掉 prefix 里的旧字体文件。

### 自动化边界 (刻意设计, 勿"补全")

重装/换机时的恢复分层 —— 只自动化两层, 第三层刻意手工:

| 层 | 机制 |
|----|------|
| Bottles 应用本体 | ✅ `flatpak-apps` 服务自动补装 (flatpak.nix, 与 com.tencent.WeChat 同机制) |
| 容器内适配 (runner/注册表/字体) | ✅ `wework-adapt` 自动重放 (本文档 §七) |
| **容器创建 + 企业微信安装** | ⚠️ **刻意不自动化**: 容器与 prefix 靠 `@persist` 保留 (本机重装即恢复); 清 persist/换新机时手工建容器 + 装企业微信 —— Windows 安装器静默参数不保证可靠、官方下载 URL 随版本漂移, 自动化维护成本高于收益 |

同样刻意不做的: bottle 内 Windows 版 ToDesk 的安装自动化 (wine 下根本跑不起来,
见「已排除的路线」)。

---

## 八、黑窗根因定位 (2026-09-17 实机取证)

本节更正 §2.1 的根因表述。方法: 重建 bottle (caffe-10.0 + 企业微信 5.0.11.6018 +
`wework-adapt`) 后在**企业微信运行中**逐步取证 —— 导出 X 窗口像素为 PNG、抓屏比对、
`niri msg windows` 查合成器侧、Xwayland 24.1.13 / satellite master 源码核对。

### 8.1 结论: 一个"设计上透明"的 ARGB 顶层窗被当作不透明黑渲染

因果链 (逐步实测):

1. **CEF 硬件加速开启时**, 企业微信除主窗 (300x420, Depth 24) 外另建一个 X 窗:
   **372x492, Depth 32, 无名, IsViewable** —— 比主窗大。
2. 它的 `Parent window id` 是 **root**(`xwininfo -id <win>` 实测) —— **不是主窗的子窗**。
3. 因为是 root 直接子窗, satellite **会接管它** (`src/xstate/mod.rs:362` 的判据正是
   `parent == root`) → 它有**自己的 Wayland surface** → niri 里是一个**独立浮动窗**。
   实测 `niri msg windows`: 主窗 id 44 (`企业微信`, 200x280 逻辑), 该窗 id 45 (标题空,
   248x328 逻辑), 浮在主窗之上且更大。
4. 导出该窗内容为 PNG: **整窗透明 (alpha=0), 只有一圈白色圆角边框** —— 它是个"窗口
   外框/阴影"窗, 设计上就该透出下面的主窗。
5. 像素统计: 该窗 X 侧 pixmap 中 **alpha=0 占 76.8%**, 不透明像素约 6%; 而屏幕同一
   区域的实测是 **76.6% 黑 / 5.7% 白** —— 比例几乎完全吻合。
   → **透明区域 (rgba 0,0,0,0) 被当作不透明黑显示, 整块盖住主窗。**

主窗本身内容**完全正常** (导出 PNG 是登录二维码界面, 98.7% 纯白)。所以故障不是
"应用没画出来", 而是**一个本该透明的覆盖窗被渲染成了黑**。

### 8.2 已排除的假设 (含我自己走过的弯路)

| 假设 | 结论 |
|------|------|
| satellite 捕获 32 位窗口失败 | ❌ satellite **无像素路径**(全仓无 `XGetImage`/`CopyArea`/`mmap`/`memfd`/`EGL`), 只转发 buffer; `convert_wenum` 是忠实换类型不改格式 |
| X 服务端内容是黑的 | ❌ X 侧内容正确(导出 PNG 可见), 黑在下游 |
| Xwayland 设了 opaque region | ❌ rootless 模式下**不设** —— 唯一调用点在非 rootless 的 `xwl_create_root_surface()` |
| Xwayland 选错 buffer 格式 | ❌ depth 32 → `ARGB8888`, shm (`shm_format_for_depth`) 与 GBM (`gbm_format_for_depth`) 两条路径都是 |
| **niri 窗口规则 `match title="^$"` → `opacity 0.0`** | ❌ **试过且有害**: 主窗**打开那一刻标题还是空的**, 也被 `^$` 匹配 → 整个企业微信变透明; 而 niri **不会**在标题后来补上时重新求值。niri 侧看不到 X 窗口的深度, 也没有别的属性能区分外框窗与主窗 → **此路不通** (已回滚)。教训: 想在合成器侧拦截, 必须用"窗口打开瞬间就确定"的属性 |
| **早期用"Depth-32 当子窗"做的合成复现** | ⚠ **拓扑搞错了** —— 那是**子窗**(无自己的 surface), 行为是"父窗绘制被封死", 与本故障完全不同。记录在此避免重蹈: **判断拓扑必须先看 `xwininfo -id <win>` 的 Parent, 不能只看 `-root -tree` 的缩进** |

### 8.3 alpha 丢失层: 已定位到 niri 的 dmabuf 路径 (2026-09-18)

**结论: niri(smithay)在合成 linux-dmabuf 送来的 ARGB buffer 时会丢掉 alpha;
同样的 buffer 走 wl_shm 则完全正常。**

取证 (未动主会话: 另起 `xwayland-satellite :1` 做实验):

1. **协议追踪** (`WAYLAND_DEBUG=1` 挂在 satellite 上) —— 两个方向都是同一个格式:

   ```
   # Xwayland -> satellite
   create_immed(new id wl_buffer#25, 1897, 2130, 875713089, 0)
   # satellite -> niri
   -> zwp_linux_buffer_params_v1@41.create_immed(wl_buffer@42, 1897, 2130, 875713089, 0)
   ```
   `875713089` = `0x34325241` = `AR24` = `DRM_FORMAT_ARGB8888`。且该 surface
   **没有任何 `set_opaque_region`** (追踪里 0 次, satellite 源码里也没有)。
   → Xwayland 与 satellite 都是清白的, alpha 一路都在。

2. **A/B 对照** —— 测试窗内容 = 全透明 + 一块不透明标记; 两次都是同一几何
   (1265x1420 逻辑)、都聚焦, 只换 Xwayland 的渲染路径:

   | 渲染路径 | buffer | 屏幕"新增黑" |
   |---|---|---|
   | glamor (默认) → **dmabuf** | `AR24` | **46.0%** (≈ 整窗面积 48.7%) |
   | `-glamor none` → **wl_shm** | `AR24` | **9.9%** (那部分是 niri 给聚焦窗画的阴影) |

   → **只换传输路径, 结果就正常了** ⇒ 责任在 niri 的 dmabuf 导入/合成。

**为什么只在 NVIDIA 出现**: dmabuf 导入是驱动相关路径 (NVIDIA 的 modifier/EGL
纹理导入与 Mesa 不同)。

**旁证**: niri 日志里 `smithay::backend::renderer::gles: [GL] GL_INVALID_VALUE
error generated. Size and/or offset out of range.` —— 报错的是 **niri 自己的渲染器**
(最初这条曾被误记成 Xwayland 的错误)。

### 8.4 解决方法

| 层 | 手段 | 有效性 |
|----|------|--------|
| **CEF (根治)** | 禁 XWeb 硬件加速 (策略注册表, 已声明式) | **实测有效** —— 不再创建那个 ARGB 外框窗 |
| **窗口管理 (兜底)** | `wework-fix` unmap 该窗 | **实测有效** —— 机制就是"移走那块黑"; 代价是打断 CEF 合成 → 重建时闪 1~2 帧 |
| satellite / niri 改动 | 任何改动 | satellite 不在像素路径上; niri 无"强制不透明"规则且不实现 `wp_alpha_modifier_v1` |
| 上游 | 让合成链路尊重 X11 ARGB 窗的 alpha | 需先在 §8.3 定位到具体层 |

### 8.5 附带发现: `wework-fix` 的进程门禁会被 wrapper 骗到

门禁扫 `/proc/*/cmdline` 找 `WXWork.exe`。实测下列**残留进程**会让它误判"企业微信运行中":

- `timeout 1800 flatpak run ... bottles-cli run -b Work -e 'C:\...\WXWork.exe'` (启动器 wrapper)
- `bwrap --args 76 -- bottles-cli run ...` (flatpak 沙箱宿主)
- `crashpad_handler.exe` (路径含 `WXWork`)

后果: **`wework-adapt` 一直跳过**。09-17 实机重建时卡了 6 轮 (22:29~22:37), 直到手工
按 PID 清掉这些残留才跑通。且这些进程 `bottles-cli stop` 不一定回收。
**已修 (2026-09-17)**: 判据改为按 **comm** 匹配 (`comm` 以 `WXWork` 开头 ——
覆盖 `WXWork.exe` / `WXWorkWeb.exe` / `WXWorkUpgrader.exe`)。wrapper 的 comm 是
`bash`/`timeout`/`bwrap`/`crashpad_handle`, 不会再误判。

### 8.6 复现器 / 取证脚本

`~/.local/share/argb-repro/` (纯 ctypes 调 libX11, 不需要编译器和 X11 头文件):

| 脚本 | 用途 |
|------|------|
| `dump2png.py` | **关键**: 把任意 X 窗口内容导出为 PNG 并打印 alpha 分布 —— 本次定位靠它 |
| `live-probe.py` | 就地统计某窗口的颜色/近黑占比 |
| `exp2.py` / `exp3.py` | 早期合成复现 (注: 用的是**子窗**拓扑, 结论见 §8.2 末行) |
| `win-bisect.py` | `XCreateWindow` 组合二分。记一个坑: 深度与父窗不同的窗口若走 `CWBorderPixmap`/`CWBackPixmap` 的 `CopyFromParent`/`ParentRelative` 分支, X server 直接 `BadMatch`, 必须带 `CWBorderPixel` |

### 8.7 重建 bottle 的实操 (本次走通, 补 §七「自动化边界」)

```bash
# 1. runner 落到 runners/ (bottles-cli 认这个值才肯用; 缺包时静默失败)
#    URL/md5 见 adapt.sh 头部; 包内顶层目录要 strip 一层
# 2. 建容器
flatpak run --command=bottles-cli com.usebottles.bottles new \
  --bottle-name Work --environment application --arch win64 --runner caffe-10.0
# 3. 改参数 (Application 环境默认 dxvk=true, 需改回文档配置)
flatpak run --command=bottles-cli com.usebottles.bottles edit -b Work \
  --params 'dxvk:false,vkd3d:false,renderer:gdi'
# 4. 装企业微信 —— NSIS 安装器, /S 静默; 安装包在 ~/Downloads 时需一次性放开沙箱可见
flatpak run --filesystem=/home/wbb/Downloads:ro --command=bottles-cli \
  com.usebottles.bottles run -b Work -e /home/wbb/Downloads/WeCom_5.0.11.6018.exe /S
# 5. 声明式适配 (runner 已是则跳过; 写策略注册表 + 字体替换)
systemctl --user start wework-adapt
```

注意: 第 4 步装完 (1.8G) 后安装器的收尾进程可能长时间不退出, 用 `bottles-cli stop -b Work`
收尾; 若 `stop` 后仍有残留, 按 PID 清理再跑第 5 步 (见 §8.5)。

### 8.8 守护改造: 轮询 → X 事件驱动 (2026-09-17)

**动机**: 1 秒轮询意味着每新建一个窗口/弹框, 那块黑最坏停留 1 秒 = **可见闪烁**
(即用户反馈的"还是会有闪烁的黑框")。原实现选轮询的两条理由**现在都不成立**:

| 原理由 | 现状 |
|--------|------|
| "故障 ARGB 窗是孙窗, root 的 SubstructureNotify 收不到" | ❌ 基于搞错的拓扑。实测故障窗 `Parent window id` = **root**, 是直接子窗, 事件完全收得到 |
| "Xlib 长连接在 satellite 重启时抛异常杀死进程" | ✅ 仍成立 —— 但现在接得住: X 连接断开时进程干净退出, `Restart=on-failure` + `RestartSec=3` 拉起, 重启后首轮全量清扫兜底 |

**改法** (`fixPy`, 纯 ctypes 直连 libX11, 不再需要 xwininfo/xdotool 子进程):

- root 上 `XSelectInput(SubstructureNotifyMask)`, 循环收 `MapNotify` → 判窗 → `XUnmapWindow`
- `XGetWindowAttributes` 读 depth/map_state/class, `XGetClassHint` 读类名, `XFetchName` 判断是否无名
- 兜底: 每 5 秒 `XQueryTree(root)` 全量清扫一次 (**只扫 root 直接子窗** —— 非 root 子窗不可能有自己的 surface, 也就不会显示出来)
- 进程门禁改按 **comm** (见 §8.5)
- `RestartSec` 10 → 3

**效果实测** (合成一个「无名 + wxwork 类名 + Depth 32 + 500x400」的 root 子窗, 三次):

```
建窗 1789658169.280 → unmap 1789658169.281   延迟 0.001 秒
建窗 1789658172.288 → unmap 1789658172.289   延迟 0.001 秒
建窗 1789658175.284 → unmap 1789658175.285   延迟 0.001 秒
```

**~1ms**, 比 1 秒轮询快约 1000 倍。
（对照组: 把测试窗的 WM_CLASS 去掉后不会被误伤, 判据仍精确。）

**但"0.1ms"只代表守护进程反应有多快, 不代表屏幕上那一帧有多快 —— 实测仍会"闪一下"。**
原因是个**赢不了的竞态**: 应用 map 窗口时, Xwayland 是在**同一次请求处理里**就创建
wl_surface 并把 buffer 提交给 niri 的(Xwayland 就是 X server 本身), 而守护作为外部
客户端只能等 MapNotify 事件 —— 提交早已发生。**事后 unmap 这条路的天花板就是一帧。**

→ 要根治只剩一条路: **让 alpha 被尊重**(见 §8.3)。transparent 真的透明之后,
这些外框窗根本不可见, 不闪、不黑角、整窗也不会黑, 守护可一并退役。

**踩坑 (移植时丢掉的语义)**: 新守护第一版**漏掉了真实的黑框** —— 实测那些窗的
`WM_NAME` **存在但为空字符串**(`XFetchName` 返回 1、指针非 NULL、内容 `""`), 而
判据写成了"指针非 NULL 即有名" → 那个 1897x2130 的大黑框一次都没被摘过, 表现为
"点击/最大化后仍有黑框"。`xwininfo` 的 `(has no name)` 对**空串和缺属性都这么打印**,
所以旧的轮询版天然没这个坑。**移植到 Xlib 时要把"空串 == 无名"显式写出来。**
回归用例: `WM_NAME=''` 应被摘 (实测 0.1ms), `WM_NAME='OpenapiWebviewWarningTips'`
应保留 (实测不摘) —— 两个方向都验过。

### 8.9 ~~最终方案: Xwayland 走 shm~~ —— **已回滚 (2026-09-18 当晚)**

> **结论: `-glamor none` (shm) 虽能修 alpha, 但会破坏鼠标输入, 不可用, 已回滚。**
> 下面的实现与验证记录保留, 作为「不是所有"渲染正常"的方案都能用」的实证。

**为什么回滚** (归因过程):

| 测试组合 | 鼠标点击 |
|----------|----------|
| 守护开 + shm | 坏 |
| 守护停 + shm (外框窗显示) | **还是坏** → 排除守护的 unmap |
| **全新启动的实例** + shm | **还是坏** → 排除应用状态 |
| 剩下唯一变量 | **`-glamor none`** |

与文档 §三「已排除的路线」里最初的记录一致 —— 那条 `-glamor none` 有问题**本来是
对的**, 是我在 A/B 里看到"大窗渲染/转发正常"就把它判成误判, **改错了**。
教训: **渲染正常 ≠ 可用**。Xwayland 关掉 glamor 后 DRI3/Present 一并失效,
Wine/CEF 的呈现路径失败很可能连带弄坏它的事件循环 —— 这类问题只有**实际点一下**
才暴露, 光看抓屏看不出来。

真因 (niri 的 dmabuf alpha 丢失) 取证结论仍然成立; 现状 = **dmabuf +
守护用 XShape 清空外框窗** (见 §8.10)。

### 8.10 守护改用 XShape 清空外框窗 (2026-09-18 收尾)

**为什么不再用 unmap**: unmap 之后 satellite **不会把 wl_buffer detach**, Wayland
surface 仍留着**最后一帧**(那圈白色圆角边框) → niri 里留下一个"幽灵窗": 看不见
却又占位、且那圈白边**一直显示**, 就是用户报的"竖条纹"。

**改法**: 用 XShape 把外框窗的 **Bounding 区剪成 0 面积**, 窗口保持 mapped:

```python
xe.XShapeCombineRectangles(dpy, wid, 0, 0, 0, None, 0, 0, 0)   # Bounding/Set/空
```

- 窗口还在 → 应用的事件路径完全不受影响 (**只剪 Bounding, 不动 Input**)
- 可见区为空 → 什么都不画 → 既没有黑块也没有白条, 也没有 ghost
- 回读验证: `XShapeQueryExtents` → `bounding_shaped=1, 区域 0x0` ✓
- 托盘窗 (explorer.exe) 仍用 unmap (它没有这个问题)

依赖加了 `pkgs.libxext`。



`modules/home/niri/default.nix` 里声明了一个 wrapper:

```nix
xwayland-satellite-shm = pkgs.writeShellScript "xwayland-satellite" ''
  exec ${pkgs.xwayland-satellite}/bin/xwayland-satellite "$@" -glamor none
'';
home.file.".local/bin/xwayland-satellite".source = xwayland-satellite-shm;
```

原理: niri 没有给 xwayland-satellite 传参的配置项, 而 niri 是按 PATH 找可执行文件的
—— `~/.local/bin` 在 niri 的 PATH 里排第一, 所以 niri spawn "xwayland-satellite"
时命中这个 wrapper, 它再 exec 真身并追加 `-glamor none` (satellite 把该值翻译成
Xwayland 的 `-shm`)。

**实测生效** (`ps` 可见 Xwayland 带 `-shm`), 且:

- 那个 1932x2166 的 Depth-32 外框窗现在 `IsViewable` 而**背后的企业微信窗口内容完全
  正常** —— 修复前它一 IsViewable 整个应用就变黑;
- 右键菜单圆角干净, 不再有黑框/闪烁。

**代价**: X11 窗口全部走 CPU 拷贝 (而非 GPU dmabuf)。办公类应用无感; 游戏/视频类
X11 应用会有性能损失。**niri 修好 dmabuf alpha 后本 wrapper 应退役。**

**守护怎么办 (2026-09-18 复盘更正)**: ARGB 判据 **必须保留**。曾一度以为 alpha
修好后那些外框窗"本来就该显示"而把判据摘掉 —— 实测那是错的: 外框窗的内容是
"全透明 + 一圈白色圆角边框", 设计上围着应用窗画边框, 但 **niri 把它当独立窗口
摆放**, 边框围不住应用窗 → 应用窗左边缘出现一条**游离的白色竖条** (实测 8px,
`rgb(216,230,244)`; 用像素比对确认过: 守护停掉时出现, unmap 掉立即消失)。
niri 自己会画窗口阴影, 应用这圈是多余且错位的 → 仍需 unmap。
代价是与应用拉锯 (实测 2 分钟 39 次 unmap), 可接受。

另: 当年那条"点击失效"**与 unmap 无关** —— 真凶是同时跑着两个企业微信实例
(`bottles-cli stop` 没杀掉旧的那个), 陈旧实例的窗口盖在上面吞掉了点击。
教训: 重启企业微信前先确认 `ps -eo comm | grep WXWork` 真的空了。

**教训**: 我曾把"Xwayland 用 `-glamor none` 时大窗不转发 + GL 错误"记进「已排除的
路线」, 据此认为 shm 路径不可用。实际上那条 GL 错误来自 **niri 的渲染器**, 与
shm 路径能不能转发窗口无关; 本次实测 `-glamor none` 下 1897x2130 的大窗转发与
显示都正常。**别把 A 层的错误日志当成 B 层不可用的证据。**

### 8.11 "白条纹"的真凶: ARGB 外框窗的边框 (2026-09-18 收尾)

**现象**: 应用窗内容**里面**有一条白色竖线 (用户描述"看着是一个框的左侧的竖向边");
右键菜单弹出时它比菜单还长、一直延伸出去。

**真凶**: 就是 §8.10 那个 **ARGB 外框窗**(内容 = 全透明 + 一圈白色圆角边框)。
本该围着应用窗画边框, 但 **niri 把它当独立窗口摆放**, 边框围不住应用窗 → 落进了
应用内容里, 表现为一条游离的白色竖线。判据: **unmap 掉它, 线立刻消失**。

**我在这上面绕了三圈, 教训值得记**:

1. **量错了线就得出错的结论**。窗口最外缘其实**还**有一条 niri 的 focus ring
   (青色 `rgb(118,173,159)`, 与本问题无关, 是用户 `config.kdl` 里配的
   `active-gradient #88d6bb→#a8cbe2`)。我量到那条青线, 颜色对上焦点环, 就宣布
   "真凶是焦点环" —— 而用户指的是**内容里面**那条白线。**两条线相距只有几像素,
   动手前必须先确认"用户指的是哪一条"**, 而不是找一条符合自己假设的线。
2. **unmap → XShape 那次改动是错的**: XShape 挡不住 Xwayland 呈递的 buffer ——
   窗口照样显示。改回 unmap 后线立刻消失。**"更优雅的做法"没有实测前不要替换
   已经验证有效的做法。**
3. 用户报"失去焦点也还在"其实是因为**要检查就得点一下, 一点焦点又回来** ——
   判断某个装饰是否随焦点变化, 必须由脚本切焦点 + 抓图对比, 不能靠手点。
