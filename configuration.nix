# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];
  ### Bootloader
  ## 使用 systemd-boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  ### filesystems
  boot.supportedFilesystems = [
    "btrfs"
  ];
  ### zram-generator
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
  ### Hibernate
  boot.resumeDevice = "/dev/disk/by-uuid/e517f0da-e89b-4c38-8414-c01df0c4469b";
  boot.kernelParams = [
    "resume_offset=140544"
  ];

  ### Flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  ### 安装 unfree（非自由许可证）软件
  nixpkgs.config = {
    allowUnfree = true;
  };

  ### hostname
  networking.hostName = "wbb"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  ### TimeZone
  # Set your time zone.
  time.timeZone = "Asia/Shanghai";

 environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    TERMINAL = "kitty";
  };

  users.users.wbb = {
    description = "wbb";
    isNormalUser = true;
    home = "/home/wbb";
    shell = pkgs.bashInteractive;
    ignoreShellProgramCheck = true;
    hashedPassword = "$y$j9T$7I/q8iYwksjdKEHcEJmH.1$D52/8Z0YQLKk.e4PzhTPSKcvvN/J4sQfP18KFo.CqxA";
    extraGroups = ["wheel" "networkmanager" "audio" "input" "video" "docker" "kvm" "libvirtd"];
  };
  services.greetd.settings.default_session = {
    command = "${pkgs.niri}/bin/niri-session";
    user = "wbb";
  };
  nix.settings.substituters = [
    "https://mirrors.cernet.edu.cn/nix-channels/store"
    "https://cache.nixos.org/"
  ];

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  ### Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "zh_CN.UTF-8";
    LC_MEASUREMENT = "zh_CN.UTF-8";
    LC_NUMERIC = "zh_CN.UTF-8";
    LC_PAPER = "zh_CN.UTF-8";
    LC_CTYPE = "zh_CN.UTF-8";
  };
  console = {
    font = "Lat2-Terminus16";
    keyMap = lib.mkDefault "us";
    useXkbConfig = true; # use xkb.options in tty.
  };
  services.blueman.enable = true;

  # Enable sound.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;


  programs.firefox.enable = true;
  programs.bash.enable = true;
  ### Niri
  programs.niri = {
    enable = true;
  };
  services.xserver.enable = false;
  hardware.graphics.enable = true;
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  programs.neovim.enable = true;
  programs.git = {
    enable = true;
  };
  xdg.portal.enable = true;

  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-gtk
  ];

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    wineWow64Packages.waylandFull
    winetricks
    google-chrome
    pciutils # lspci
    ffmpeg-full
    libva-utils
    curl
    wget
    cachix
    btrfs-progs
    snapper
    waybar
    foot
    fish
    kitty
    fuzzel
    mako
    swaybg
    wl-clipboard
    grim
    slurp
  ];

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  services.greetd.enable = true;
  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
    system.stateVersion = "26.05"; # Did you read the comment?

}