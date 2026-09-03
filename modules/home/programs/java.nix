# Java 开发环境 —— JDK (LTS) + Gradle + Maven
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    jdk21    # LTS
    gradle
    maven
  ];

  # 显式 JAVA_HOME, gradle/maven/IDE 都能找到
  home.sessionVariables = {
    JAVA_HOME = "${pkgs.jdk21}";
  };
}
