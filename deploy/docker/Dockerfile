FROM node:22-alpine AS frontend
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --non-interactive
COPY . .
RUN yarn build:production

FROM composer:2 AS composer
FROM php:8.3-fpm-alpine
WORKDIR /app
RUN apk add --no-cache nginx supervisor su-exec curl ca-certificates mariadb-client \
      libpng-dev oniguruma-dev libzip-dev \
    && docker-php-ext-install -j$(nproc) bcmath gd mbstring pdo_mysql zip pcntl posix
COPY --from=composer /usr/bin/composer /usr/local/bin/composer
COPY . .
COPY --from=frontend /app/public/assets ./public/assets
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts \
    && composer check-platform-reqs --no-dev \
    && mkdir -p storage/logs storage/framework/cache/data storage/framework/sessions storage/framework/views bootstrap/cache /etc/nginx/gateway /run/nginx \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod +x deploy/docker/*.sh \
    && rm -f /etc/nginx/http.d/default.conf
COPY deploy/docker/nginx.conf /etc/nginx/http.d/panel.conf
COPY deploy/docker/supervisord.conf /etc/supervisord.conf
EXPOSE 80
ENTRYPOINT ["/bin/sh", "/app/deploy/docker/entrypoint.sh"]
CMD ["serve"]
