FROM composer:1.9 AS composer
FROM wordpress:cli-2.4-php7.4 AS wpcli

FROM php:7.4-fpm-alpine AS packages

ENV WORDPRESS_VERSION 5.6.4
ENV WORDPRESS_SHA1 0817a7e302dfed8addd271b27aa7c3f7c6b54415

# Install PHP extensions
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
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j "$(nproc)" \
    bcmath \
    exif \
    gd \
    mysqli \
    zip \
    ; \
    git clone --recursive --depth=1 https://github.com/kjdev/php-ext-brotli.git && cd php-ext-brotli && phpize &&  ./configure --with-libbrotli && make && make install; \
    pecl install imagick redis vips; \
    docker-php-ext-enable brotli imagick opcache redis vips

# Copy Wordpress
RUN set -ex; \
    curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
    echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c -; \
    # upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
    tar -xzf wordpress.tar.gz -C /usr/src/; \
    rm wordpress.tar.gz;

# Remove defaults from WP
RUN cd /usr/src/wordpress/wp-content/plugins/ && rm -R -- */ && rm hello.php \
    && cd /usr/src/wordpress/wp-content/themes \
    && rm -R -- */

# --------------

FROM php:7.4-fpm-alpine

RUN apk add  --no-cache --virtual .run-deps \
    bash \
    brotli \
    ghostscript \
    less \
    libzip \
    imagemagick \
    imagemagick-libs \
    sed \
    vips \
    ; \
    runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
    apk add --virtual .wordpress-phpexts-rundeps $runDeps;

# PHP extensions
COPY --from=packages /usr/local/etc/php /usr/local/etc/php
COPY --from=packages /usr/local/include/php/ /usr/local/include/php
COPY --from=packages /usr/local/lib/php /usr/local/lib/php

# Composer
COPY --from=composer /usr/bin/composer /usr/local/bin/composer

# Wordpress
COPY --from=wpcli /usr/local/bin/wp /usr/local/bin/wp
COPY --from=packages /usr/src/wordpress /usr/src/wordpress

EXPOSE 9000
CMD ["php-fpm"]
