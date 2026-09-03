# Python 开发环境 —— python3 + uv (包/虚拟环境管理器)
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    python3
    uv    # 替代 pip + venv, 管理包和虚拟环境
  ];
}
