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

已知残余限制: 右键菜单/弹框首次打开时会闪 1~2 帧黑 (毫秒级自愈), 属上游
xwayland-satellite 在 NVIDIA 上的缺陷, 不影响功能。

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

**根因链** (三层):
1. 企业微信的 CEF/XWeb 把 GPU 合成内容画在一个 **32 位 ARGB 子窗口** (Depth 32, 无名,
   常比父窗大), 在 NVIDIA + xwayland-satellite 下该子窗内容**读不到** (未初始化 GPU
   buffer), 空壳子窗盖住下层正常 GDI 绘制的 UI;
2. satellite 对运行中新建的窗口缓存首帧黑帧, 不重抓 → 双击菜单/弹框持续黑;
3. X server (satellite) 重启后 fcitx5 的 XIM 注册丢失 → 输入法失效。

**解决**:
- 策略注册表禁 XWeb 硬件加速 (见上) —— 让主窗内容回到 GDI 层;
- **wework-fix 守护服务** (`modules/home/programs/wework.nix`, 09-17 前为 wework-fix.nix): 1 秒轮询,
  自动 unmap「Depth 32 + 无名 + IsViewable + >10x10」的故障窗与 explorer 托盘窗,
  并写日志 (可审计); 实测菜单/弹框毫秒级自愈 (闪 1~2 帧黑);
- 输入法由 fcitx5 体系负责 (见上)。

**待上游根治**: xwayland-satellite 在 NVIDIA 上无法读取 32 位 ARGB 窗口内容。
上游修复后 wework-fix 守护可退役。

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
| `wework-fix` 服务 | 1s 轮询守护 | unmap 故障 ARGB 子窗 + explorer 托盘横条 (§2.1 的桌面侧兜底) |
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
