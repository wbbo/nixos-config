# 用户账户:wbb
{ pkgs, ... }:
{
  users.users.wbb = {
    description = "wbb";
    isNormalUser = true;
    home = "/home/wbb";
    # 默认 shell 为 fish;如需改回 bash,用 pkgs.bashInteractive
    shell = pkgs.fish;
    ignoreShellProgramCheck = true;

    # ⚠️ 敏感信息:用户密码哈希。生产环境建议改用 sops-nix / agenix 加密管理。
    hashedPassword = "$y$j9T$7I/q8iYwksjdKEHcEJmH.1$D52/8Z0YQLKk.e4PzhTPSKcvvN/J4sQfP18KFo.CqxA";

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
