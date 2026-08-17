{ pkgs, ... }:

let
  imSelect = "/opt/homebrew/bin/im-select";

  # ATOK は「あ」「英字」を独立した入力ソースではなく単一ソース内のモードとして扱うため、
  # 別ソースの `com.apple.keylayout.ABC` ではなく ATOK 内の英字モード ID を指定する
  # (英字モード中に `im-select` を引数なしで実行して確認した実際の ID)。
  atokRoman = "com.justsystems.inputmethod.atok36.Roman";
in
{
  # Karabiner-Elements 本体は homebrew.nix の cask 側で管理している
  # (カーネル拡張/権限まわりのリスクがあるため brew を継続)。ここは設定ファイルのみ。
  #
  # 【重要】以後 Karabiner の GUI で設定を変えないこと。
  # Karabiner は設定変更時に temp ファイル + rename でこのパスを書き換えるため、
  # その瞬間に store symlink が実ファイルに置き換わり、次の make rebuild で
  # backupFileExtension = "bak" によって黙って .bak に退避される (= 変更が消える)。
  # 起動時やデバイス着脱では書き込まないことは mtime で実測確認済み。
  # キー名や vendor_id/product_id の調査に使う EventViewer は
  # karabiner.json を書かないので普通に使ってよい。
  #
  # GUI で試行錯誤したいときは karabiner.json を一旦削除して Karabiner に実ファイルを
  # 書かせ、固まった内容をこのファイルへ移してから make rebuild で戻す。
  xdg.configFile."karabiner/karabiner.json".source =
    (pkgs.formats.json { }).generate "karabiner.json" {
      profiles = [
        {
          name = "Default profile";
          selected = true;
          virtual_hid_keyboard.keyboard_type_v2 = "ansi";

          complex_modifications.rules = [
            {
              description = "Convert Ctrl+Space to Ctrl+Shift+S";
              manipulators = [
                {
                  type = "basic";
                  from = {
                    key_code = "spacebar";
                    modifiers = {
                      mandatory = [ "control" ];
                      optional = [ ];
                    };
                  };
                  to = [
                    {
                      key_code = "s";
                      modifiers = [ "control" "shift" ];
                    }
                  ];
                }
              ];
            }

            # 上の Ctrl+Shift+S 版の代替。同じ Ctrl+Space から発火するので排他。
            {
              description = "Convert Ctrl+Space to fn (Globe)";
              enabled = false;
              manipulators = [
                {
                  type = "basic";
                  from = {
                    key_code = "spacebar";
                    modifiers = {
                      mandatory = [ "control" ];
                      optional = [ ];
                    };
                  };
                  to = [ { key_code = "fn"; } ];
                }
              ];
            }

            {
              description = "cmd+shift+l → F13 (for VSCode auxiliary bar)";
              enabled = false;
              manipulators = [
                {
                  type = "basic";
                  conditions = [
                    {
                      type = "frontmost_application_if";
                      bundle_identifiers = [ "^com\\.microsoft\\.VSCode" ];
                    }
                  ];
                  from = {
                    key_code = "l";
                    modifiers.mandatory = [ "command" "shift" ];
                  };
                  to = [ { key_code = "f13"; } ];
                }
              ];
            }

            # tmux leader (Ctrl-P) を押した瞬間に ATOK を英字モードへ強制切り替えしてから
            # Ctrl-P を転送する。prefix 入力中に IME が有効なままだと後続のキーが
            # IME の変換バッファに吸われて tmux に届かないのを防ぐ。
            #
            # alacritty.nix の keybind (command = im-select) と同じ目的だが、Ghostty の
            # keybind には外部コマンドを起動するアクションが無い (`ghostty +list-actions`
            # で確認済み) ため Karabiner 側で実現している。Karabiner は仮想 HID 層、
            # つまり IME より下で割り込むので、ATOK がかな入力モードで Ctrl-P を
            # 握っている場合でも確実に発火する点は Alacritty 版より優れている。
            #
            # shell_command は非同期に実行されるので Ctrl-P 自体の転送は遅れない。
            # 切り替えに ~200ms かかるが、効かせたいのは「次の」キーなので実用上問題ない。
            #
            # alacritty.nix を畳むときは bundle_identifiers に "^org\\.alacritty$" を足し、
            # alacritty.nix 側の Ctrl+P keybind 2 つ (command と chars) を削除する。
            {
              description = "Ghostty: Ctrl+P (tmux leader) を押したら ATOK を英字モードへ";
              manipulators = [
                {
                  type = "basic";
                  conditions = [
                    {
                      type = "frontmost_application_if";
                      bundle_identifiers = [ "^com\\.mitchellh\\.ghostty$" ];
                    }
                  ];
                  from = {
                    key_code = "p";
                    modifiers = {
                      mandatory = [ "control" ];
                      optional = [ ];
                    };
                  };
                  to = [
                    { shell_command = "${imSelect} ${atokRoman}"; }
                    {
                      key_code = "p";
                      modifiers = [ "left_control" ];
                    }
                  ];
                }
              ];
            }
          ];

          # F20/F21 は cocot46plus (自作キーボード) 側から送っているキー。
          simple_modifications = [
            {
              from.key_code = "f20";
              to = [ { pointing_button = "button4"; } ];
            }
            {
              from.key_code = "f21";
              to = [ { pointing_button = "button5"; } ];
            }
          ];

          # vendor_id / product_id は Karabiner が検出した実値 (10 進)。
          # 下 4 件は個別デバイス設定で、いずれも調査時点では未接続のため
          # 製品名は特定せず USB vendor ID の登録名のみ併記している。
          devices = [
            # 全キーボード共通: CapsLock → 左 Control
            {
              identifiers.is_keyboard = true;
              simple_modifications = [
                {
                  from.key_code = "caps_lock";
                  to = [ { key_code = "left_control"; } ];
                }
              ];
            }

            # ignore = true: Karabiner がこのデバイスのイベントを一切加工しない
            # (= 上の CapsLock → Control も含め全ルールが適用されない)
            {
              # vendor 1410 = 0x0582 (Roland), product 798 = 0x031e
              identifiers = {
                is_keyboard = true;
                vendor_id = 1410;
                product_id = 798;
              };
              ignore = true;
            }

            {
              # vendor 34948 = 0x8898 (USB-IF 未登録), product 2201 = 0x0899
              # manipulate_caps_lock_led = false: CapsLock の LED を Karabiner が制御しない
              identifiers = {
                is_keyboard = true;
                vendor_id = 34948;
                product_id = 2201;
              };
              manipulate_caps_lock_led = false;
            }

            {
              # vendor 1278 = 0x04fe (PFU), product 22 = 0x0016
              # キーボードとポインティングデバイスを兼ねる。ignore = false は
              # 「無視しない」の明示 (Karabiner のデフォルトと同じだが GUI 操作の痕跡)
              identifiers = {
                is_keyboard = true;
                is_pointing_device = true;
                vendor_id = 1278;
                product_id = 22;
              };
              ignore = false;
            }

            {
              # vendor 1149 = 0x047d (Kensington), product 65535 = 0xffff
              identifiers = {
                is_keyboard = true;
                vendor_id = 1149;
                product_id = 65535;
              };
              ignore = true;
            }
          ];
        }
      ];
    };
}
