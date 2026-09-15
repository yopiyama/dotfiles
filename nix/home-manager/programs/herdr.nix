{ ... }:

{
  # Herdr 本体・設定・自作ランチャーを同じ source of truth から管理する。
  # scripts/link.sh とは同じパスを管理しない。
  xdg.configFile."herdr/config.toml".source = ../../../.config/herdr/config.toml;
  xdg.configFile."herdr/scripts".source = ../../../.config/herdr/scripts;
}
