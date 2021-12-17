ARG RESTY_BASE_IMAGE="alpine"
ARG RESTY_BASE_IMAGE_TAG="3.15"

FROM ${RESTY_BASE_IMAGE}:${RESTY_BASE_IMAGE_TAG}

LABEL maintainer="Canger <canger@dianplus.cn>"

# Docker Build Arguments

ARG DYUPS_VERSION="v0.2.11"
ARG RESTY_INSTALL_PREFIX="/opt/openresty"

ARG RESTY_BASE_IMAGE="alpine"
ARG RESTY_BASE_IMAGE_TAG="3.15"
ARG RESTY_VERSION="1.19.9.1"
ARG RESTY_OPENSSL_VERSION="1.1.1m"
ARG RESTY_OPENSSL_PATCH_VERSION="1.1.1f"
ARG RESTY_OPENSSL_URL_BASE="https://www.openssl.org/source"
ARG RESTY_PCRE_VERSION="8.45"
ARG RESTY_PCRE_SHA256="4e6ce03e0336e8b4a3d6c2b70b1c5e18590a5673a98186da90d4f33c23defc09"
ARG RESTY_J="1"
ARG RESTY_CONFIG_OPTIONS="\
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --add-module=ngx_http_dyups_module \
    --with-compat \
    --with-file-aio \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_geoip_module=dynamic \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_image_filter_module=dynamic \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_xslt_module=dynamic \
    --with-ipv6 \
    --with-mail \
    --with-mail_ssl_module \
    --with-md5-asm \
    --with-pcre-jit \
    --with-sha1-asm \
    --with-stream \
    --with-stream_ssl_module \
    --with-threads \
    "
ARG RESTY_CONFIG_OPTIONS_MORE=""
ARG RESTY_LUAJIT_OPTIONS="--with-luajit-xcflags='-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT'"

ARG RESTY_ADD_PACKAGE_BUILDDEPS=""
ARG RESTY_ADD_PACKAGE_RUNDEPS=""
ARG RESTY_EVAL_PRE_CONFIGURE=""
ARG RESTY_EVAL_POST_MAKE=""

# These are not intended to be user-specified
ARG _RESTY_CONFIG_DEPS="--with-pcre \
    --with-cc-opt='-DNGX_LUA_ABORT_AT_PANIC -I${RESTY_INSTALL_PREFIX}/pcre/include -I${RESTY_INSTALL_PREFIX}/openssl/include' \
    --with-ld-opt='-L${RESTY_INSTALL_PREFIX}/pcre/lib -L${RESTY_INSTALL_PREFIX}/openssl/lib \
    -Wl,-rpath,${RESTY_INSTALL_PREFIX}/pcre/lib:${RESTY_INSTALL_PREFIX}/openssl/lib' \
    "

LABEL resty_image_base="${RESTY_BASE_IMAGE}"
LABEL resty_image_tag="${RESTY_BASE_IMAGE_TAG}"
LABEL resty_version="${RESTY_VERSION}"
LABEL resty_openssl_version="${RESTY_OPENSSL_VERSION}"
LABEL resty_openssl_patch_version="${RESTY_OPENSSL_PATCH_VERSION}"
LABEL resty_openssl_url_base="${RESTY_OPENSSL_URL_BASE}"
LABEL resty_pcre_version="${RESTY_PCRE_VERSION}"
LABEL resty_pcre_sha256="${RESTY_PCRE_SHA256}"
LABEL resty_config_options="${RESTY_CONFIG_OPTIONS}"
LABEL resty_config_options_more="${RESTY_CONFIG_OPTIONS_MORE}"
LABEL resty_config_deps="${_RESTY_CONFIG_DEPS}"
LABEL resty_add_package_builddeps="${RESTY_ADD_PACKAGE_BUILDDEPS}"
LABEL resty_add_package_rundeps="${RESTY_ADD_PACKAGE_RUNDEPS}"
LABEL resty_eval_pre_configure="${RESTY_EVAL_PRE_CONFIGURE}"
LABEL resty_eval_post_make="${RESTY_EVAL_POST_MAKE}"

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories

RUN \
    addgroup -S nginx \
 && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
 && apk add --no-cache --virtual .build-deps \
        build-base \
        coreutils \
        curl \
        gd-dev \
        geoip-dev \
        git \
        libxslt-dev \
        linux-headers \
        make \
        perl-dev \
        readline-dev \
        zlib-dev \
        ${RESTY_ADD_PACKAGE_BUILDDEPS} \
 && apk add --no-cache \
        gd \
        geoip \
        libgcc \
        libxslt \
        lua-sec \
        lua-socket \
        zlib \
        ${RESTY_ADD_PACKAGE_RUNDEPS} \
 && cd /tmp \
 && if [ -n "${RESTY_EVAL_PRE_CONFIGURE}" ]; then \
      eval $(echo ${RESTY_EVAL_PRE_CONFIGURE}); \
    fi \
 && cd /tmp \
 && curl -fSL "${RESTY_OPENSSL_URL_BASE}/openssl-${RESTY_OPENSSL_VERSION}.tar.gz" \
      -o openssl-${RESTY_OPENSSL_VERSION}.tar.gz \
 && tar xzf openssl-${RESTY_OPENSSL_VERSION}.tar.gz \
 && cd openssl-${RESTY_OPENSSL_VERSION} \
 && if [ $(echo ${RESTY_OPENSSL_VERSION} | cut -c 1-5) = "1.1.1" ] ; then \
      echo 'patching OpenSSL 1.1.1 for OpenResty' \
      && curl -s https://raw.githubusercontent.com/openresty/openresty/master/patches/nssl-${RESTY_OPENSSL_PATCH_VERSION}-sess_set_get_cb_yield.patch | patch -p1 ; \
    fi \
 && if [ $(echo ${RESTY_OPENSSL_VERSION} | cut -c 1-5) = "1.1.0" ] ; then \
      echo 'patching OpenSSL 1.1.0 for OpenResty' \
      && curl -s https://raw.githubusercontent.com/openresty/openresty/ed328977028c3ec3033bc25873ee360056e247cd/patches/nssl-1.1.0j-parallel_build_fix.patch | patch -p1 \
      && curl -s https://raw.githubusercontent.com/openresty/openresty/master/patches/nssl-${RESTY_OPENSSL_PATCH_VERSION}-sess_set_get_cb_yield.patch | patch -p1 ; \
    fi \
 && ./config \
      no-threads shared zlib -g \
      enable-ssl3 enable-ssl3-method \
      --prefix=${RESTY_INSTALL_PREFIX}/openssl \
      --libdir=lib \
      -Wl,-rpath,${RESTY_INSTALL_PREFIX}/openssl/lib \
 && make -j${RESTY_J} \
 && make -j${RESTY_J} install_sw \
 && cd /tmp \
 && curl -fSL https://downloads.sourceforge.net/project/pcre/pcre/${RESTY_PCRE_VERSION}/pcre-${RESTY_PCRE_VERSION}.tar.gz \
      -o pcre-${RESTY_PCRE_VERSION}.tar.gz \
 && echo "${RESTY_PCRE_SHA256}  pcre-${RESTY_PCRE_VERSION}.tar.gz" | shasum -a 256 --check \
 && tar xzf pcre-${RESTY_PCRE_VERSION}.tar.gz \
 && cd /tmp/pcre-${RESTY_PCRE_VERSION} \
 && ./configure \
      --prefix=${RESTY_INSTALL_PREFIX}/pcre \
      --disable-cpp \
      --enable-jit \
      --enable-utf \
      --enable-unicode-properties \
 && make -j${RESTY_J} \
 && make -j${RESTY_J} install \
 && cd /tmp \
 && curl -fSL https://openresty.org/download/openresty-${RESTY_VERSION}.tar.gz -o openresty-${RESTY_VERSION}.tar.gz \
 && tar xzf openresty-${RESTY_VERSION}.tar.gz \
 && cd /tmp/openresty-${RESTY_VERSION} \
 && git clone https://github.com/dianplus/ngx_http_dyups_module.git ngx_http_dyups_module \
 && cd ngx_http_dyups_module \
 && git checkout tags/${DYUPS_VERSION} \
 && cd .. \
 && eval ./configure \
           -j${RESTY_J} --prefix=${RESTY_INSTALL_PREFIX} ${_RESTY_CONFIG_DEPS} ${RESTY_CONFIG_OPTIONS} \
           ${RESTY_CONFIG_OPTIONS_MORE} ${RESTY_LUAJIT_OPTIONS} \
 && make -j${RESTY_J} \
 && make -j${RESTY_J} install \
 && cd /tmp \
 && if [ -n "${RESTY_EVAL_POST_MAKE}" ]; then \
      eval $(echo ${RESTY_EVAL_POST_MAKE}); \
    fi \
 && rm -rf \
      openssl-${RESTY_OPENSSL_VERSION}.tar.gz openssl-${RESTY_OPENSSL_VERSION} \
      pcre-${RESTY_PCRE_VERSION}.tar.gz pcre-${RESTY_PCRE_VERSION} \
      openresty-${RESTY_VERSION}.tar.gz openresty-${RESTY_VERSION} \
 && apk del .build-deps \
 && mkdir -p /var/run/openresty \
 && ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80

# Add additional binaries into PATH for convenience
ENV RESTY_DIR=${RESTY_INSTALL_PREFIX}
ENV PATH=$PATH:$RESTY_DIR/luajit/bin:$RESTY_DIR/nginx/sbin:$RESTY_DIR/bin

CMD ["openresty", "-g", "daemon off;"]

# Use SIGQUIT instead of default SIGTERM to cleanly drain requests
# See https://github.com/openresty/docker-openresty/blob/master/README.md#tips--pitfalls
STOPSIGNAL SIGQUIT
