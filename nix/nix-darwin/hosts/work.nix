{ ... }:

{
  # 仕事用 Mac 固有の設定。導入時にここへ差分 (追加 cask / package 等) を書く。
  # homebrew.casks / homebrew.brews はリスト型オプションなので、
  # homebrew.nix の共通設定と自動でマージされる (++ で結合される)。例:
  # homebrew.casks = [ "datagrip" ];
}
