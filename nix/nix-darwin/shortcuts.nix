# キーボードショートカット (システム設定 > キーボード > キーボードショートカット)。
# `defaults export com.apple.symbolichotkeys -` の現在値から生成したもの。
#
# nix-darwin は AppleSymbolicHotKeys を dict 丸ごと上書きするため、
# 変更したいショートカットだけでなく全エントリをここに列挙しておく必要がある。
# parameters = [ASCII コード (65535 = なし), キーコード, 修飾キー bitmask]
# 反映にはログアウトか再起動が必要。
{
  system.defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
    "7" = { enabled = true; value = { type = "standard"; parameters = [ 65535 120 262144 ]; }; };
    "8" = { enabled = true; value = { type = "standard"; parameters = [ 65535 99 262144 ]; }; };
    "9" = { enabled = true; value = { type = "standard"; parameters = [ 65535 118 262144 ]; }; };
    "10" = { enabled = true; value = { type = "standard"; parameters = [ 65535 96 262144 ]; }; };
    "11" = { enabled = true; value = { type = "standard"; parameters = [ 65535 97 262144 ]; }; };
    "12" = { enabled = true; value = { type = "standard"; parameters = [ 65535 122 262144 ]; }; };
    "13" = { enabled = true; value = { type = "standard"; parameters = [ 65535 98 262144 ]; }; };
    "15" = { enabled = false; };
    "16" = { enabled = false; };
    "17" = { enabled = false; };
    "18" = { enabled = false; };
    "19" = { enabled = false; };
    "20" = { enabled = false; };
    "21" = { enabled = false; value = { type = "standard"; parameters = [ 56 28 1835008 ]; }; };
    "22" = { enabled = false; };
    "23" = { enabled = false; };
    "24" = { enabled = false; };
    "25" = { enabled = false; value = { type = "standard"; parameters = [ 46 47 1835008 ]; }; };
    "26" = { enabled = false; value = { type = "standard"; parameters = [ 44 43 1835008 ]; }; };
    "27" = { enabled = true; value = { type = "standard"; parameters = [ 64 33 1048576 ]; }; };
    "28" = { enabled = false; value = { type = "standard"; parameters = [ 51 20 1179648 ]; }; };
    "29" = { enabled = false; value = { type = "standard"; parameters = [ 51 20 1441792 ]; }; };
    "30" = { enabled = false; value = { type = "standard"; parameters = [ 52 21 1179648 ]; }; };
    "31" = { enabled = false; value = { type = "standard"; parameters = [ 52 21 1441792 ]; }; };
    "32" = { enabled = true; value = { type = "standard"; parameters = [ 65535 126 9175040 ]; }; };
    "33" = { enabled = true; value = { type = "standard"; parameters = [ 65535 125 11272192 ]; }; };
    "34" = { enabled = true; value = { type = "standard"; parameters = [ 65535 126 9306112 ]; }; };
    "35" = { enabled = true; value = { type = "standard"; parameters = [ 65535 125 11403264 ]; }; };
    "36" = { enabled = true; value = { type = "standard"; parameters = [ 65535 103 0 ]; }; };
    "37" = { enabled = true; value = { type = "standard"; parameters = [ 65535 103 131072 ]; }; };
    "51" = { enabled = true; value = { type = "standard"; parameters = [ 64 33 1572864 ]; }; };
    "52" = { enabled = true; value = { type = "standard"; parameters = [ 100 2 1572864 ]; }; };
    "53" = { enabled = true; value = { type = "standard"; parameters = [ 65535 107 0 ]; }; };
    "54" = { enabled = true; value = { type = "standard"; parameters = [ 65535 113 0 ]; }; };
    "55" = { enabled = true; value = { type = "standard"; parameters = [ 65535 107 524288 ]; }; };
    "56" = { enabled = true; value = { type = "standard"; parameters = [ 65535 113 524288 ]; }; };
    "57" = { enabled = true; value = { type = "standard"; parameters = [ 65535 100 262144 ]; }; };
    "59" = { enabled = true; value = { type = "standard"; parameters = [ 65535 96 1048576 ]; }; };
    "60" = { enabled = false; value = { type = "standard"; parameters = [ 32 49 393216 ]; }; };
    "61" = { enabled = false; value = { type = "standard"; parameters = [ 32 49 786432 ]; }; };
    "62" = { enabled = true; value = { type = "standard"; parameters = [ 65535 111 0 ]; }; };
    "63" = { enabled = true; value = { type = "standard"; parameters = [ 65535 111 131072 ]; }; };
    "64" = { enabled = false; value = { type = "standard"; parameters = [ 65535 49 1048576 ]; }; };
    "65" = { enabled = true; value = { type = "standard"; parameters = [ 65535 49 1572864 ]; }; };
    "70" = { enabled = true; value = { type = "standard"; parameters = [ 100 2 1310720 ]; }; };
    "73" = { enabled = true; value = { type = "standard"; parameters = [ 65535 53 1048576 ]; }; };
    "75" = { enabled = false; value = { type = "standard"; parameters = [ 65535 100 0 ]; }; };
    "76" = { enabled = false; value = { type = "standard"; parameters = [ 65535 100 131072 ]; }; };
    "79" = { enabled = true; value = { type = "standard"; parameters = [ 65535 123 11272192 ]; }; };
    "80" = { enabled = true; value = { type = "standard"; parameters = [ 65535 123 11403264 ]; }; };
    "81" = { enabled = true; value = { type = "standard"; parameters = [ 65535 124 11272192 ]; }; };
    "82" = { enabled = true; value = { type = "standard"; parameters = [ 65535 124 11403264 ]; }; };
    "98" = { enabled = false; value = { type = "standard"; parameters = [ 47 44 1179648 ]; }; };
    "118" = { enabled = false; value = { type = "standard"; parameters = [ 65535 18 262144 ]; }; };
    "119" = { enabled = false; value = { type = "standard"; parameters = [ 65535 19 262144 ]; }; };
    "120" = { enabled = false; value = { type = "standard"; parameters = [ 65535 20 262144 ]; }; };
    "121" = { enabled = false; value = { type = "standard"; parameters = [ 65535 21 262144 ]; }; };
    "156" = { enabled = true; value = { type = "standard"; parameters = [ 65535 49 393216 ]; }; };
    "163" = { enabled = false; value = { type = "standard"; parameters = [ 110 45 1572864 ]; }; };
    "164" = { enabled = false; value = { type = "standard"; parameters = [ 65535 65535 0 ]; }; };
    "176" = { enabled = false; value = { type = "SAE1.0"; }; };
    "179" = { enabled = false; };
    "233" = { enabled = false; value = { type = "standard"; parameters = [ 109 46 1048576 ]; }; };
    "235" = { enabled = true; value = { type = "standard"; parameters = [ 65535 65535 0 ]; }; };
    "237" = { enabled = true; value = { type = "standard"; parameters = [ 102 3 8650752 ]; }; };
    "238" = { enabled = true; value = { type = "standard"; parameters = [ 99 8 8650752 ]; }; };
    "239" = { enabled = true; value = { type = "standard"; parameters = [ 114 15 8650752 ]; }; };
  };
}
