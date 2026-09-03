# 本机定制: 主机名 / 用户名 (非机密, 纳入版本控制; 接收者改为自己的)
{ config, lib, ... }:
{
  hostName = "wbb";                 # 主机名
  mainUser = lib.mkForce "wbb";     # 用户名 (覆盖模板默认 user)
  mihomo-ui = "zashboard";          # mihomo WebUI: metacubexd / yacd / zashboard

  # GTX 960M (Maxwell) 启用专有驱动: 下面两行必须**成对**取消注释 (漏掉 open
  # 那行不会被 eval 断言拦截 —— legacy_580 也带 open 模块变体, 会静默加载失败)。
  # 背景: stable(595)分支与 open 内核模块均不支持 Maxwell, 当前方案下 960M
  # 保持闲置 (无专有/nouveau, 等效空设备); 取消注释后 960M 常开 (+5~15W),
  # CUDA 12.x 可用 (CUDA 13 已移除 sm_50, 将来 nixpkgs 默认切 13 需钉 cuda_12_x)。
  # hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  # hardware.nvidia.open = lib.mkForce false;
}
