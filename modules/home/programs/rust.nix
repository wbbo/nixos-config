# Rust 开发环境 —— rustup 管理 toolchain
# cargo/rustc 经 rustup 装到 ~/.cargo/bin (见 fish.nix 的 fish_add_path)
{ pkgs, ... }:
{
  home.packages = with pkgs; [ rustup ];

  home.sessionVariables = {
    RUSTUP_HOME = "$HOME/.rustup";
    CARGO_HOME = "$HOME/.cargo";
  };
}
