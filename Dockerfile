FROM composer:2.3 AS composer
FROM wordpress:cli-2.6-php7.4 AS wpcli

FROM php:7.4-fpm-alpine
# FROM php:7.4-fpm-alpine AS packages

ENV WORDPRESS_VERSION 5.9.3
ENV WORDPRESS_SHA1 cab576e112c45806c474b3cbe0d1263a2a879adf

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
        git \
        icu-dev \
        imagemagick-dev \
        libc-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        make \
        vips-dev \
    ; \
    \
    docker-php-ext-configure gd \
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
    git clone --recursive --depth=1 https://github.com/kjdev/php-ext-brotli.git && cd php-ext-brotli && phpize &&  ./configure --with-libbrotli && make && make install; \
# WARNING: imagick is likely not supported on Alpine: https://github.com/Imagick/imagick/issues/328
# https://pecl.php.net/package/imagick
    pecl install imagick-3.6.0 redis vips; \
    docker-php-ext-enable brotli imagick opcache redis vips; \
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

# FROM php:7.4-fpm-alpine

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
    sed \
    vips \
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
	\
	! { ldd "$extDir"/*.so | grep 'not found'; }; \
# check for output like "PHP Warning:  PHP Startup: Unable to load dynamic library 'foo' (tried: ...)
	err="$(php --version 3>&1 1>&2 2>&3)"; \
	[ -z "$err" ]

# PHP extensions
# COPY --from=packages /usr/local/etc/php /usr/local/etc/php
# COPY --from=packages /usr/local/include/php/ /usr/local/include/php
# COPY --from=packages /usr/local/lib/php /usr/local/lib/php

# Composer
COPY --from=composer /usr/bin/composer /usr/local/bin/composer

# Wordpress
COPY --from=wpcli /usr/local/bin/wp /usr/local/bin/wp
# COPY --from=packages /usr/src/wordpress /usr/src/wordpress

EXPOSE 9000
CMD ["php-fpm"]
