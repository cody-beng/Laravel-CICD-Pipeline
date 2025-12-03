#!/bin/sh
set -e

ENV_FILE=/var/www/html/.env

if [ ! -f "$ENV_FILE" ]; then
    cp /var/www/html/.env.example "$ENV_FILE"
fi

echo ":package: Checking Composer dependencies..."
if [ ! -d "vendor" ]; then
  composer install --no-dev --optimize-autoloader --no-interaction
fi

echo ">> Checking APP_KEY..."
if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "base64:" ]; then
  echo ">> No APP_KEY set, generating one..."
  php artisan key:generate --force
else
  echo ">> APP_KEY already set."
fi

echo ">> Waiting for database..."
dockerize -wait tcp://db:3306 -timeout 60s

echo ">> Running migrations..."
php artisan migrate --force || echo ":warning: Migration skipped (already up to date)"
php artisan db:seed || echo ":warning: Seeder skipped (already up to date)"

echo ">> Caching config, routes, views..."
php artisan config:clear
php artisan route:clear
php artisan view:clear
# php artisan optimize:clear

php artisan config:cache
php artisan route:cache
php artisan view:cache

echo ">> Starting PHP-FPM..."
exec php-fpm -F
      - ./:/var/www/html
    environment:
      - APP_ENV=production
