FROM php:8.2-apache

# Nainštalujeme potrebné knižnice pre PostgreSQL, aby sa PHP vedelo pripojiť k databáze
RUN apt-get update && apt-get install -y libpq-dev \
    && docker-php-ext-install pdo pdo_pgsql pgsql

# Skopírujeme tvoj webový kód (zatiaľ len index.php) do kontajnera
COPY index.php /var/www/html/

# Nastavíme práva, aby Apache mohol čítať súbory
RUN chown -R www-data:www-data /var/www/html

EXPOSE 80
