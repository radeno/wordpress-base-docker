FROM composer:2.8 AS composer
FROM wordpress:cli-2.12-php8.4 AS wpcli

FROM php:8.4-fpm-alpine

ENV WORDPRESS_VERSION 6.8.8
ENV WORDPRESS_SHA1 5e0ea40fe47f936b5e69d9c2e406fe163341273a

# ENV LDFLAGS="-lmimalloc"
# install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
RUN set -ex; \
    \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        autoconf \
        brotli-dev \
        freetype-dev \
        gcc \
        ghostscript-dev \
        icu-dev \
        imagemagick-dev libheif-dev \
        libavif-dev \
        libc-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libwebp-dev \
        lz4-dev \
        libzip-dev \
        make \
        vips-dev \
        mimalloc-dev \
    ; \
    \
    docker-php-ext-configure gd \
        --with-avif \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    ; \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        mysqli \
        zip \
    ; \
    pecl install brotli vips imagick-3.8.1; \
    # Use igbinary or msgpack
    pecl install igbinary; \
    pecl install --configureoptions 'enable-redis-igbinary="yes" enable-redis-lz4="yes"' redis; \
    docker-php-ext-enable brotli imagick redis igbinary vips; \
    rm -r /tmp/pear; \
    \
	apk del --no-network .build-deps

# Copy Wordpress
RUN set -ex; \
    curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
    echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c -; \
    # upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
    tar -xzf wordpress.tar.gz -C /usr/src/; \
    rm wordpress.tar.gz; \
    # Remove defaults from WP
    cd /usr/src/wordpress/wp-content/plugins/ && rm -R -- */ && rm hello.php \
    && cd /usr/src/wordpress/wp-content/themes \
    && rm -R -- */

# --------------

RUN apk add  --no-cache --virtual .run-deps \
    bash \
    brotli \
    ghostscript \
    icu \
    less \
    libgomp \
    libjpeg-turbo \
    libpng \
    libwebp \
    libzip \
    imagemagick \
    imagemagick-libs \
    libheif \
    libavif \
    lz4 \
    sed \
    vips \
    mimalloc \
    ; \
# some misbehaving extensions end up outputting to stdout 🙈 (https://github.com/docker-library/wordpress/issues/669#issuecomment-993945967)
    out="$(php -r 'exit(0);')"; \
    [ -z "$out" ]; \
    err="$(php -r 'exit(0);' 3>&1 1>&2 2>&3)"; \
    [ -z "$err" ]; \
    \
    extDir="$(php -r 'echo ini_get("extension_dir");')"; \
    [ -d "$extDir" ]; \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive "$extDir" \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-network --virtual .wordpress-phpexts-rundeps $runDeps; \
    apk del --no-network .build-deps; \
    \
    ! { ldd "$extDir"/*.so | grep 'not found'; }; \
# check for output like "PHP Warning:  PHP Startup: Unable to load dynamic library 'foo' (tried: ...)
    err="$(php --version 3>&1 1>&2 2>&3)"; \
    [ -z "$err" ]

# Composer
COPY --from=composer /usr/bin/composer /usr/local/bin

# Wordpress
COPY --from=wpcli /usr/local/bin/wp /usr/local/bin

# Preload mimalloc for PHP at runtime
RUN ln -sf libmimalloc.so.2 /usr/lib/libmimalloc.so

ENV LD_PRELOAD="/usr/lib/libmimalloc.so"

EXPOSE 9000
CMD ["php-fpm"]
