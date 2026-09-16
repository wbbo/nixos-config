# 打印 / 扫描 —— CUPS + Avahi(局域网发现) + Epson EcoTank L3250 相关
#
# 设备: Epson L3250 (ESC/P-R 世代喷墨一体机, 支持 AirPrint / IPP Everywhere)。
# 本机只用它的**打印**(含手机/其他设备经局域网打印); 扫描不启用, 原因见文末注释。
# 策略 —— 打印优先免驱:
#   * CUPS 自带的 cups-filters/ghostscript 即含 IPP Everywhere 支持, 局域网里
#     打印机被 Avahi/mDNS 自动发现, cups-browsed 自动建好免驱队列 (不写死 IP,
#     打印机换地址自愈), 零厂商驱动。社区实测 L3250 在 Fedora 上就是"无需驱动"
#     直接选到 IPP 队列跑通的; 效果不达标再加 services.printing.drivers 的
#     epson-escpr (见下, 已备注释)。
#
# 管理界面: http://localhost:631 (CUPS 默认只监听回环, 安全; 要共享给局域网/VM
# 再加 services.printing.listenAddresses + 防火墙放行 631)
{ pkgs, ... }:
{
  services.printing.enable = true;

  # 厂商驱动 (默认空 —— 优先免驱; 需要时取消注释, 再从 CUPS 里选对应 PPD):
  # services.printing.drivers = [ pkgs.epson-escpr ];    # ESC/P-R 官方驱动 (L3250 先试这个)
  #                                                     # 若 lpinfo -m | grep -i l3250 找不到 PPD,
  #                                                     # 换 pkgs.epson-escpr2 (ESC/P-R2, 新机型)

  # 局域网发现: Avahi/mDNS —— AirPrint / IPP 打印机自动出现在 CUPS 里
  services.avahi = {
    enable = true;
    nssmdns4 = true;     # 让程序能解析 <主机名>.local
    openFirewall = true; # 放行 mDNS (5353/udp)
  };

  ### 声明式打印队列 (可选)
  # 取消注释并把 IP 换成打印机的实际地址。**前提是 IP 固定** (路由器做 DHCP
  # 保留, 或打印机设静态 IP) —— 否则 IP 一变队列就失效 (CUPS 里表现为打印机无响应)。
  # 不想写死 IP 也行: 只留上面的 enable + avahi, 在 localhost:631 里手动加一次
  # (重装后需重加, 这就是声明式与手动的取舍)。
  # hardware.printers.ensurePrinters = [{
  #   name = "Epson-L3250";
  #   deviceUri = "ipp://192.168.x.x/ipp/print";   # ← 改成实际 IP
  #   model = "everywhere";                        # 免驱 (= lpadmin -m everywhere)
  # }];
  # hardware.printers.ensureDefaultPrinter = "Epson-L3250";

  ### 扫描 —— 本机不启用 (2026-09-17 决定)
  # L3250 的扫描在开源栈走不通, 三条路都试过:
  #   * eSCL/AirScan 免驱: 本机不支持 (eSCL 端点 404, 也不广播 _uscan._tcp);
  #   * SANE epson2 网络后端: 能发现设备 (epson2:net:...), 但起不了扫描会话
  #     (sane_start: Error during device I/O; 端口 1865 开着时同样失败);
  #   * Epson 官方 epsonscan2: 网络模式要它的 non-free 插件 (nixpkgs 无此包);
  #     且打印机几分钟就深睡, 睡后扫描端口直接不响应。
  # 文档电子化改走"手机拍照 + OCR", 故不装扫描组件 (SANE/epsonscan2 一并撤掉)。
  #
  # 将来若要 USB 直连扫描 (epsonscan2 的 USB 模式不需要私有插件), 装回:
  #   hardware.sane.enable = true;
  #   environment.systemPackages = [ pkgs.epsonscan2 pkgs.simple-scan ];
  # 想再试 eSCL 路线时另加: hardware.sane.extraBackends = [ pkgs.sane-airscan ];

  # USB 直连打印机时 (本机目前是网络接法, 保留备用): ipp-usb 把支持
  # IPP everywhere 的 USB 打印机变成本机可访问的网络打印机, 同样免驱。
  # services.ipp-usb.enable = true;
}
