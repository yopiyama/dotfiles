{ ... }:

{
  # .config/mise/config.toml から移行
  programs.mise = {
    enable = true;
    globalConfig = {
      tools = {
        node = "lts";
        "npm:eslint_d" = "latest";
      };
    };
  };
}
