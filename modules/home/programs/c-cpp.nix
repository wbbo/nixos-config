# C/C++ 开发环境 —— gcc 编译器 + clang-tools (clangd/format) + 构建工具
# 注意: 不装 pkgs.clang (它与 gcc 的 bin/c++ wrapper 冲突), 用 clang-tools 提供 clangd 等
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gcc
    clang-tools  # clangd / clang-format / clang-tidy
    cmake
    ninja
    gnumake
    pkg-config
  ];
}
