# orangefox_build_cepheus

Xiaomi Mi 9 (cepheus) 用の OrangeFox(fox_12.1) を、ROM の 4.19 カーネルでビルドするための環境です。
ソース本体(`12.1/`)は含みません。同期スクリプトで取得します。

- device tree: https://github.com/amiami5/device_xiaomi_cepheus_orangefox (ブランチ `fox_12.1`)
- 対象 ROM: lineage 系 Android 16(カーネル 4.19.325, develop-419)、非 A/B の retrofit dynamic partitions

## 手順

```bash
# 1. ソースを取得(repo sync。約 70GB。上限対策で -j4)
./orangefox_sync.sh --branch 12.1 --path "$PWD/12.1"

# 2. 公式の device tree を自前のものに置き換える
rm -rf 12.1/device/xiaomi/cepheus
git clone -b fox_12.1 https://github.com/amiami5/device_xiaomi_cepheus_orangefox \
    12.1/device/xiaomi/cepheus

# 3. ビルド
./build-cepheus.sh        # 並列数は引数で指定(省略時 6)
```

成果物: `12.1/out/target/product/cepheus/OrangeFox-R12.0-Unofficial-cepheus.img`

## 元の OrangeFox 同期スクリプトからの変更点

- `repo init` / `repo sync` の `--depth=1` を外した(push 時の問題を避けるため)
- `repo sync` を `-j4` に変更(googlesource の HTTP 429 対策)
- `patches/` の参照先を、このリポジトリ直下に合わせた

## 焼き方・起動

```cmd
fastboot flash recovery OrangeFox-R12.0-Unofficial-cepheus.img
```

- 起動は、完全に電源を切ってから **音量上 + 電源**。ROM の電源メニューの recovery からも入れる
- recovery パーティションからの起動には **recovery dtbo の同梱が必須**(ヘッダ v2 で空だと bootloader が fastboot に落ちる)。device tree の `prebuilt/dtbo.img` がそれ
- `fastboot boot` は、音量下 + 電源で入った fastboot からのみ使える(失敗後の縮退した fastboot では `Load Error`)

## ROM を更新したとき、再ビルドが要るか

recovery は ROM の userspace を使わないため、**ROM の更新のほとんどは再ビルド不要**。
カーネルと暗号化まわりが変わったときだけ、device tree の `prebuilt/` などを入れ替えて再ビルドする。

| ROM 側の変更 | 再ビルド | 入れ替え先 |
|---|---|---|
| カーネルのソース・config の変更(`CONFIG_UNICODE`、FS_ENCRYPTION、DM_DEFAULT_KEY、UFS 暗号化まわり、ドライバ修正) | **要** | `prebuilt/Image.gz` |
| dts の変更(dtb が変わる) | **要** | `prebuilt/dtbs/`、`prebuilt/dtbo.img` |
| 暗号化方式の変更(fstab の `fileencryption` / `wrappedkey` の指定) | **要** | `recovery/root/system/etc/recovery.fstab`、`BoardConfig.mk` |
| keymaster / gatekeeper の HAL バージョン、TZ ファームウェアの更新 | **要** | `recovery/root/` の blob |
| Android のメジャーバージョン更新(synthetic password の形式変更など) | 場合による | OrangeFox 側の復号実装が追いつくか確認する |
| アプリ・framework・system / vendor イメージ、SELinux ポリシーの更新 | 不要 | - |

判断に迷ったら、ROM のカーネルと同じ内容かを見る。同じなら再ビルド不要。

```bash
md5sum <ROM のソース>/out/target/product/cepheus/kernel \
       12.1/device/xiaomi/cepheus/prebuilt/Image.gz
```

カーネルが変わっていても、変更が /data の復号に関係しない場合(例: 音声ドライバのログ出力の修正)は、
次にカーネルを更新するときにまとめて取り込めば足りる。

## ROM のカーネルを更新したとき

ROM 側(`out/target/product/cepheus/`)の成果物を device tree に入れ直す。

| 入れ替え先(device tree) | 元 |
|---|---|
| `prebuilt/Image.gz` | `kernel` |
| `prebuilt/dtbs/*.dtb` | ROM のビルドした dtb |
| `prebuilt/dtbo.img` | `dtbo.img`(**ヘッダの total_size に切り詰める**。recovery パーティションに収めるため) |

## 復号(/data)について

userdata は casefold 付き ext4 + FBE v2 + wrapped key。次の設定が揃って初めて復号できる。

- カーネル `CONFIG_UNICODE`(ROM の 4.19 で有効)
- `TW_SKIP_ADDITIONAL_FSTAB`(ext4 の実体に `inlinecrypt` を付ける)
- `OF_FIX_DECRYPTION_ON_DATA_MEDIA`(DE 鍵投入後に /data を再 mount しない)
- keymaster 4.1 / gatekeeper 1.0 / qseecomd と、framework manifest、libc++ のスタブ
