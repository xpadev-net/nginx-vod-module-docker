# ビルドステージ
FROM debian:trixie-slim AS builder

# Workflowから受け取る値（未指定時は既存ロジックにフォールバック）
ARG NGINX_VERSION=""
ARG NGX_VOD_REF=""

# 必要なパッケージのインストール
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    libpcre2-8-0 \
    libpcre2-dev \
    zlib1g \
    zlib1g-dev \
    libssl-dev \
    libgd-dev \
    libxml2 \
    libxml2-dev \
    uuid-dev \
    git \
    wget \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# nginxの最新stable版をダウンロード
WORKDIR /usr/local/src
RUN NGINX_LATEST=$(wget -qO- http://nginx.org/en/download.html | \
    grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' | \
    head -1 | \
    sed 's/nginx-\(.*\)\.tar\.gz/\1/') && \
    if [ -n "$NGINX_VERSION" ]; then \
        NGINX_LATEST="$NGINX_VERSION"; \
    elif [ -z "$NGINX_LATEST" ]; then \
        NGINX_LATEST="1.25.2"; \
    fi && \
    echo "Using nginx version: $NGINX_LATEST" && \
    wget https://nginx.org/download/nginx-${NGINX_LATEST}.tar.gz && \
    tar -xzvf nginx-${NGINX_LATEST}.tar.gz && \
    mv nginx-${NGINX_LATEST} nginx

# nginx-vod-moduleのソースコードをクローン
WORKDIR /usr/local/src
RUN git clone https://github.com/dio-az/nginx-vod-module.git && \
    cd nginx-vod-module && \
    if [ -n "$NGX_VOD_REF" ]; then \
        git checkout "$NGX_VOD_REF"; \
    fi

# NGINXのビルドとインストール
WORKDIR /usr/local/src/nginx
RUN ./configure \
    --add-module=../nginx-vod-module \
    --with-file-aio \
    --with-threads \
    --with-http_ssl_module \
    --with-http_sub_module \
    --with-http_gzip_static_module \
    --with-http_gunzip_module \
    --with-http_addition_module \
    --with-http_slice_module \
    --with-http_dav_module \
    --with-http_v2_module \
    --with-http_auth_request_module \
    --with-http_realip_module \
    --with-http_stub_status_module \
    --prefix=/usr/share/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --http-log-path=/var/log/nginx/access.log \
    --error-log-path=/var/log/nginx/error.log \
    --lock-path=/var/lock/nginx.lock \
    --pid-path=/run/nginx.pid \
    --modules-path=/usr/lib/nginx/modules \
    --http-client-body-temp-path=/var/lib/nginx/body \
    --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
    --http-proxy-temp-path=/var/lib/nginx/proxy \
    --http-scgi-temp-path=/var/lib/nginx/scgi \
    --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
    --with-pcre-jit \
    --with-cc-opt='-g -O2 -flto=auto -ffat-lto-objects -flto=auto -ffat-lto-objects -fstack-protector-strong -Wformat -Werror=format-security -fPIC -Wdate-time -D_FORTIFY_SOURCE=2 -O3 -mpopcnt -DNGX_VOD_MAX_TRACK_COUNT=256 -mavx2' \
    --with-ld-opt='-Wl,-Bsymbolic-functions -flto=auto -ffat-lto-objects -flto=auto -Wl,-z,relro -Wl,-z,now -fPIC' \
    --with-compat \
    --with-debug \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-stream_ssl_preread_module && \
    make -j$(nproc) && \
    make install

# 必要なライブラリを特定してコピー
RUN mkdir -p /tmp/libs && \
    ldd /usr/share/nginx/sbin/nginx 2>/dev/null | \
    awk '/=>/ {print $3}' | \
    grep -v '^$' | \
    xargs -I '{}' sh -c 'if [ -f "{}" ]; then cp -L "{}" /tmp/libs/ 2>/dev/null || true; fi' && \
    ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        if [ -f /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 ]; then \
            cp /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /tmp/libs/; \
        elif [ -f /lib64/ld-linux-x86-64.so.2 ]; then \
            cp /lib64/ld-linux-x86-64.so.2 /tmp/libs/; \
        fi; \
    elif [ "$ARCH" = "aarch64" ]; then \
        if [ -f /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 ]; then \
            cp /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 /tmp/libs/; \
        fi; \
    fi

# 実行ステージ
FROM gcr.io/distroless/base-debian13

# 必要なライブラリをコピー（アーキテクチャに応じて適切なディレクトリにコピー）
COPY --from=builder --chown=root:root /tmp/libs/ /lib/

# nginxバイナリとモジュールをコピー
COPY --from=builder --chown=root:root /usr/share/nginx /usr/share/nginx

# 作業ディレクトリ
WORKDIR /usr/share/nginx

# ポート公開
EXPOSE 80 443

# nginxを起動
ENTRYPOINT ["/usr/share/nginx/sbin/nginx"]
CMD ["-g", "daemon off;"]
