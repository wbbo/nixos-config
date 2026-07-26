# 用户账户:wbb
{ pkgs, config, ... }:
{
  users.users.wbb = {
    description = "wbb";
    isNormalUser = true;
    home = "/home/wbb";
    # 默认 shell 为 fish;如需改回 bash,用 pkgs.bashInteractive
    shell = pkgs.fish;
    ignoreShellProgramCheck = true;

    # 密码哈希由 sops-nix 解密注入 (来源: secrets/secrets.yaml)
    hashedPasswordFile = config.sops.secrets.wbb-password-hash.path;

    extraGroups = [
      "wheel" # sudo
      "networkmanager"
      "audio"
      "input"
      "video"
      "docker"
      "kvm"
      "libvirtd"
    ];
  };
}
