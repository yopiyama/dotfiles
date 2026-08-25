{ config, lib, pkgs, ... }:

let
  cfg = config.dotfiles.googleCloudSdk;
in
{
  # コンポーネント (kubectl, gke-gcloud-auth-plugin 等) は `gcloud components install`
  # では入れられない。Nix store が read-only で gcloud が自分の SDK ディレクトリを
  # 書き換えられないため必ず失敗する。代わりに withExtraComponents で必要な
  # コンポーネントを同梱した gcloud を組み立てる。マシン固有のコンポーネントは
  # hosts/*.nix からこのオプションで足す (gcloud 本体は両方の Mac で使う)。
  options.dotfiles.googleCloudSdk.extraComponents = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    example = lib.literalExpression "with pkgs.google-cloud-sdk.components; [ kubectl ]";
    description = "gcloud に同梱する追加コンポーネント (pkgs.google-cloud-sdk.components の要素)。";
  };

  config.home.packages = [
    (pkgs.google-cloud-sdk.withExtraComponents cfg.extraComponents)
  ];
}
