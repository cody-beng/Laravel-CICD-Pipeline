FROM nginx:alpine

# Create non-root user
RUN addgroup -g 1001 -S up_training_nginx && \
    adduser -S up_training_nginx -u 1001 -G up_training_nginx

# Set permissions for logs and www
RUN mkdir -p /var/www/html \
    && chown -R up_training_nginx:up_training_nginx /var/www/html /var/log/nginx /var/cache/nginx /var/run

# Copy configs
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf
