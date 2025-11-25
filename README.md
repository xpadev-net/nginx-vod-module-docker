# nginx-vod-module Docker Image

このプロジェクトは、`gcr.io/distroless/base-debian13`イメージ上でnginxとnginx-vod-moduleを動作させるDockerイメージを構築します。

nginx-vod-moduleは、サーバー上にある動画ファイルを動的にHLSやMPDに変換してくれるnginx拡張モジュールです。

## 特徴

- **Distrolessベース**: セキュリティを重視した最小限のランタイム環境
- **マルチステージビルド**: ビルドサイズを最適化
- **最新版nginx**: 最新のstable版のnginxを使用
- **GitHub Actions**: 自動ビルドとプッシュに対応

## ビルド方法

### ローカルでビルド

```bash
docker build -t nginx-vod .
```

### GitHub Actionsによる自動ビルド

このリポジトリには、GitHub Actionsを使用してDockerイメージを自動的にビルドし、GitHub Container Registryにプッシュするワークフローが含まれています。

ワークフローは以下の場合にトリガーされます：

- `main`または`master`ブランチへのプッシュ
- プルリクエストの作成
- タグのプッシュ（`v*`形式）
- 手動実行（workflow_dispatch）

ビルドされたイメージは `ghcr.io/<ユーザー名>/<リポジトリ名>` にプッシュされます。

## 使用方法

### 基本的な使用方法

```bash
docker run -d \
  -p 80:80 \
  -p 443:443 \
  -v /path/to/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v /path/to/movies:/path/to/movies:ro \
  nginx-vod
```

### 設定ファイルの例

Qiita記事を参考にした設定例：

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name  example.com;
    root  /path/to/root;
    include /etc/nginx/default.d/*.conf;
    client_max_body_size 100M;

    vod_mode local; #基本はlocalでok、remoteを入れるとhttp経由でmp4を取れる
    vod_fallback_upstream_location /fallback;
    vod_last_modified 'Sun, 19 Nov 2000 08:52:00 GMT';
    vod_last_modified_types *;
    vod_metadata_cache metadata_cache 1024m;
    vod_response_cache response_cache 512m;
    vod_manifest_segment_durations_mode accurate; #hlsなどのセグメント長を実際の数値に合わせる
    vod_segment_duration 10000; #セグメント長はお好みで
    vod_align_segments_to_key_frames on; #onにしない(キーフレームに合わせない)と音だけとかになる

    gzip on;
    gzip_types application/vnd.apple.mpegurl;

    open_file_cache          max=1000 inactive=5m;
    open_file_cache_valid    2m;
    open_file_cache_min_uses 1;
    open_file_cache_errors   on;
    aio on;

    location / {
        vod dash;
        vod hls;
        alias /path/to/movie/;
    }
}
```

### HLS配信へのアクセス

コンテナを起動後、以下のURLでHLS配信にアクセスできます：

```
http://ホスト名/動画へのパス/master.m3u8
```

HLS対応プレイヤーでこのURLにアクセスすると動画を再生できます。

## トラブルシューティング

### VMでうまく動かない

`vod_mode`が`local`の際にvirtioなどを使用するとエラーが出ることがあります。その場合はNFSなどを経由してみてください。

### セグメントのURLがすべてhttpになっている

プロキシなどを噛ませているなどでサーバーがhttpで接続を受け付けている場合、セグメントのURLもhttpになります。SSLを有効にしてみてください。

### hls.jsでセグメント間に抜けが発生する

サーバー内に以下の設定を追記してみてください：

```nginx
vod_manifest_segment_durations_mode accurate;
vod_segment_duration 10000;
vod_align_segments_to_key_frames on;
```

## 注意事項

- **認証**: 本番環境では認証を別途設定することをおすすめします
- **設定ファイル**: 設定ファイルはボリュームマウントで外部から提供する必要があります
- **動画ファイル**: 動画ファイルもボリュームマウントで提供してください

## 参考資料

- [nginx-vod-module公式リポジトリ](https://github.com/kaltura/nginx-vod-module)
- [Qiita記事: nginx-vod-moduleでon-the-flyなhls配信環境を作る](https://qiita.com/xpadev-net/items/714eddf2ceb3d0ef78a7)

## ライセンス

このプロジェクトはMITライセンスの下で提供されています。

