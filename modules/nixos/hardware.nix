# 硬件:图形、蓝牙、CPU 微码、固件
{ pkgs, lib, ... }:
{
  ### CPU 微码固定双开 (Intel/AMD): 内核按 CPU 厂商匹配加载, 另一家无效但无害;
  ### install.sh 已移除微码检测 (hardware-configuration.nix 不再包含微码行)。
  ### Haswell TSC_DEADLINE errata 要求 ≥0x22 (装前实测 0x1c 报 Firmware Bug)。
  ### 用普通字面量而非 mkDefault: 手动 nixos-generate-config 接管时其微码行是
  ### mkDefault(1000), 字面量(100) 直接覆盖, 不会同优先级冲突; 需要禁用时
  ### 在 local.nix 用 mkForce 覆盖。
  hardware.cpu.intel.updateMicrocode = true;
  hardware.cpu.amd.updateMicrocode = true;

  ### 可再分发固件 (linux-firmware): iwlwifi 无线固件等。
  ### 装前 /run/current-system/firmware 仅有 regulatory.db,
  ### iwlwifi 报 "no suitable firmware found" → Wi-Fi 设备完全缺失。
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  ### 图形加速(NixOS 24.11+ 用 hardware.graphics 替代旧 hardware.opengl)
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver  # Intel VA-API (iHD): Broadwell(GEN8)+ 平台
      intel-vaapi-driver  # Intel VA-API (i965): 老平台 GEN4~9.5; 两包共存 libva 自动选
    ];
  };

  ### NVIDIA 专有驱动 (通用): 适用 Turing+ 现代卡 (RTX 20/30/40/50, 如 4090)。
  ### Maxwell 等老卡 (GTX 960M) 需 legacy_580 分支 (见 local.nix 备用注释)。
  ### 无 N 卡的机器: 驱动闲置 (模块加载/probe 失败仅 dmesg NVRM 报错; open
  ### 模块下另有 systemd-modules-load failed, 见下方取舍记录), 代价是构建产物
  ### 含 nvidia blob。
  ###
  ### nouveau/nova_core/nvidiafb 屏蔽由 nixpkgs nvidia 模块自动处理, 无需手动
  ### blacklist —— 但注意耦合: 该屏蔽依赖 videoDrivers 含 "nvidia", 若某机器
  ### override 移除 nvidia 驱动, 屏蔽随之失效, 带 N 卡的机器 (如 960M) 需自行
  ### 补 boot.blacklistedKernelModules, 否则 nouveau 复活 (MMIO FAULT + 耗电)。
  ###
  ### 驱动栈构成 (重要, 勿误解): open=true 只是「内核模块层」用 NVIDIA 官方
  ### open-gpu-kernel-modules (MIT, Turing+ 专用), 「用户态层」仍是 NVIDIA 专有
  ### 闭源 blob (videoDrivers=nvidia) —— 即官方混合体, 不是 nouveau/NVK 开源栈。
  ###
  ### 取舍记录:
  ### - open=true (mkDefault): Turing+ 官方推荐 (闭源模块功能等价, 仅 RTX 50
  ###   等新架构必须 open)。注意: open 模块会把 nvidia_uvm 加进 boot.kernelModules
  ###   (nixpkgs nvidia.nix), 无卡/老卡 (Maxwell) 机器开机 modprobe 失败 →
  ###   systemd-modules-load failed (degraded 观感 + dmesg NVRM 噪音, 无功能
  ###   影响); 此类机器在 local.nix 覆盖 open=false (见其注释)。
  ### - powerManagement=false: nvidia-sleep 的 chvt 63 是 Xorg 时代遗留, niri
  ###   纯 Wayland 下有 VT 抖动/重复挂起报告; Turing+ 笔记本需 RTD3 时再开。
  ### - nvidiaPersistenced 不开 (nixpkgs 默认 false): 无可用驱动时该服务
  ###   Restart=always 重启循环至 failed; CUDA 计算场景再开。
  ###
  ### 纯声明式选择: 驱动按机器在 hosts/<hostDir>/local.nix 声明 (mkForce 覆盖
  ### package/open 等), 不做运行时探测 —— NixOS 哲学: 配置决定, 而非环境探测。
  services.xserver.videoDrivers = [ "nvidia" ];  # 纯 Wayland 也用此开关选驱动
  hardware.nvidia = {
    modesetting.enable = true;       # Wayland/niri 必须 (GBM)
    open = lib.mkDefault true;       # open 内核模块 (Turing+ 推荐; 老卡 local.nix 覆盖 false)
    powerManagement.enable = lib.mkDefault false;  # 暂关, 原因见上方取舍说明
  };

  ### 蓝牙
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
}
