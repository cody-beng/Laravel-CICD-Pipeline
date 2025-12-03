## **Github Actions with EC2 Instance**

### Create EC2 instance
- Login to AWS console, If you don't have account yet, signup and use the Free Tier
- Create EC2 instance
  - select "EC2" from home console
  - on EC2 page, click "Lunch instance", then select "Lunch instance" from dropdown menu
  - on lunch instance page, on "Name and tags" section, enter your instance name
  - on "Application and OS Images" section, select "Ubuntu" or "Linux"
  - check t2.micro if it is enough for you.
  - on "Key pair (login)" section, click "Create new key pair"
  - on key pair modal, enter your "Key pair name" then click "Create key pair" button. This will download your key pair so keep it somewhere safe in your laptop/PC
  - on "Network settings" section, click "Select existing security group", then on "Common security groups" select "Linux-SG"
  - on the bottom right corner click "Lunch instance"
  - after successfully create lunch the instance from the success dialog

### Connect to EC2 instnce
```bash
ssh -i "your_directory_to_pem/ssh_pem_file_name.pem" <host-user>@ec2-[server_ip_address].ap-southeast-1.compute.amazonaws.com
```

### Install docker
```bash
sudo dnf update -y && sudo dnf install -y docker
sudo mkdir -p /usr/libexec/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
  -o /usr/libexec/docker/cli-plugins/docker-compose
sudo chmod +x /usr/libexec/docker/cli-plugins/docker-compose
```

### Start and enable docker
```bash
sudo systemctl start docker && sudo systemctl enable docker
```

### Test your docker
```bash
docker ps

# you should see something like this
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
```

- Note: If you cannot run docker ps, run the command below
```bash
sudo usermod -aG docker $USER
```

### Let's create a project folder
```bash
sudo mkdir up-training
```

### CD to your project folder and create `docker-compose.yml`
```bash
cd up-training && touch docker-compose.yml
```

### Edit `docker-compose.yml` and paste the code below
```bash
sudo nano docker-compose.yml
```

`docker-compose.yml`
```Dockerfile
services:
  nginx:
    build:
      context: ./docker/nginx
      dockerfile: Dockerfile
    ports:
      - "80:80"
      - "443:443"
    container_name: kreditinfo_nginx
    volumes:
      - ./docker/nginx/default.conf:/etc/nginx/conf.d/default.conf
      - ./public:/var/www/html
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    networks:
      - up_training_network
    depends_on:
      - php

  php:
    image: php:8.2-fpm
    container_name: kreditinfo_php
    restart: unless-stopped
    working_dir: /var/www/html
    volumes:
      - ./:/var/www/html
      - ./docker/php/uploads.ini:/usr/local/etc/php/conf.d/uploads.ini
    networks:
      - up_training_network

  db:
    image: mysql:8.0
    container_name: kreditinfo_db
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: ${DB_DATABASE}
      MYSQL_ROOT_PASSWORD: ${ROOT_PASSWORD}
      MYSQL_USER: ${DB_USERNAME}
      MYSQL_PASSWORD: ${adm1n_krEditInfo}
    command: --default-authentication-plugin=mysql_native_password
    ports:
      - "3306:3306"
    volumes:
      - kreditinfo_data:/var/lib/mysql
      - ./docker/mysql/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - up_training_network

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    container_name: kreditinfo_phpmyadmin
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      PMA_HOST: db
      PMA_ARBITRARY: 0
      UPLOAD_LIMIT: 512M
    networks:
      - up_training_network
    depends_on:
      - db

networks:
  up_training_network:

volumes:
  kreditinfo_data:
```

### Create needed folders and configuration needed for the deployment
- On your project folder run
  ```bash
  mkdir docker && cd docker && mkdir mysql && cd mysql && touch init.sql && sudo nano init.sql
  ```
  - paste the code below:
    ```mysql
    GRANT ALL PRIVILEGES ON *.* TO 'admin_up_training_user'@'%' IDENTIFIED BY 'UP_trAining' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
    ```
  - To save, prese CTRL + X, then press Shift + Y, then press Enter
  - create .env file inside mysql folder
    ```bash
    touch .env && sudo nano .env
    ```
    - paste the env below:
      ```text
      MYSQL_DATABASE=up_training
      MYSQL_USER=admin_up_training_user
      MYSQL_PASSWORD=UP_trAining
      MYSQL_ROOT_PASSWORD=UP_trAining
      ```
  - CD to docker root folder, run the command
    ```bash
    mkdir php && cd php && touch uploads.ini && sudo nano uploads.ini
    ```
    - paste the code below:
      ```php
      upload_max_filesize = 1024M
      post_max_size = 1024M
      memory_limit = 2048M
      expose_php = Off
      ```
  - CD to docker root folder, run the command
    ```bash
    mkdir nginx && cd nginx && touch Dockerfile && sudo nano Dockerfile
    ```
    - paste the code below:
      ```Dockerfile
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
      ```
  - On the nginx folder, run the command
    ```bash
    touch nginx.conf && sudo nano nginx.conf
    ```
    - paste the code below:
      ```bash
        user  up_training_nginx;
        worker_processes  auto;

        events {
            worker_connections 1024;
        }

        http {
            server_tokens off;
            add_header Server "";
            include /etc/nginx/mime.types;
            sendfile        on;
            keepalive_timeout  65;
            include /etc/nginx/conf.d/*.conf;
        }
      ```
  - On the nginx folder, run the command
    ```bash
    touch nginx.conf && sudo nano default.conf
    ```
    - paste the code below:
      ```bash
        server {
            listen 80;
            server_name _;

            # --- SECURITY BLOCKS FIRST ---
            # Block sensitive folders
            location ~* /(app|vendor|storage|bootstrap|config|database|resources|routes|tests|node_modules|docker|data|stubs)/ {
                deny all;
                return 404;
            }

            # Block hidden files (.env, .git, etc.)
            location ~ /\.(?!well-known).* {
                deny all;
            }

            # Block PHP execution in uploads/storage
            location ~* /(?:uploads|storage)/.*\.php$ {
                deny all;
            }

            # Block /assets
            location ~* ^/assets/ {
                deny all;
                return 404;
            }

            # Laravel application
            location / {
                try_files $uri $uri/ /index.php?$query_string;
            }

            # PHP-FPM for Laravel
            location ~ \.php$ {
                include fastcgi_params;
                fastcgi_pass up_training:9000;
                fastcgi_index index.php;
                fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                fastcgi_param PATH_INFO $fastcgi_path_info;

                # PHP errors (optional)
                # remove this on production
                fastcgi_param PHP_VALUE "display_errors=1 \n error_reporting=E_ALL";

                fastcgi_buffers 16 16k;
                fastcgi_buffer_size 32k;
            }
        }
      ```


### Dockerhub
- Signin to your dockerhub account. If you don't have an account yet, signup
- Create a repository `up_training`
- Grab your username and password, save it securely somewhere in your device


### Github Secrets
- Go to project settings and go to `Secrets and variables` > `Actions`
- Click `New repository secret`, create everything below are the needed in our CI/CD
- Enter name DOCKER_USER and secrets -> secrets will your dockerhub username
- Enter name EC2_HOST and secrets -> secrets will be your server user
- Enter name SSH_TEST_PRIVATE_KEY and secrets -> secrets will be your private SSH key

- **Note** - If you don't have the ssh key, go to your server and run the code below
  ```bash
  cd ~/.ssh && 
  ```


### Github Actions

- Create `.github/workflows` on your project root directory
- CD to `.github/workflows` and create `pull-request.yml`
- Copy and paste below

```yml
name: Up Training CI Tests

on:
  pull_request:
    branches:
      - develop

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      mysql:
        image: mysql:8.0
        ports:
          - 3306:3306
        env:
          MYSQL_ROOT_PASSWORD: password
          MYSQL_DATABASE: laravel_test
        options: >-
          --health-cmd "mysqladmin ping -uroot -ppassword"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 3

    steps:
      - uses: actions/checkout@v3

      - name: Set up PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.2'
          extensions: mbstring, bcmath, pdo_mysql, curl, xml, zip

      - name: Install Composer dependencies
        run: composer install --prefer-dist --no-progress --no-suggest

      - name: Copy .env.example to .env
        run: cp .env.example .env

      - name: Generate app key
        run: php artisan key:generate

      - name: Run migrations
        env:
          DB_CONNECTION: mysql
          DB_HOST: 127.0.0.1
          DB_PORT: 3306
          DB_DATABASE: laravel_test
          DB_USERNAME: root
          DB_PASSWORD: password
        run: |
          echo "Waiting for MySQL to be ready..."
          for i in {1..30}; do
            if mysql -h 127.0.0.1 -P 3306 -u root -p password -e "SELECT 1;" >/dev/null 2>&1; then
              echo "MySQL is ready!"
              break
            fi
            echo "Waiting..."
            sleep 2
          done
          php artisan migrate --force

      - name: Run tests
        env:
          DB_CONNECTION: mysql
          DB_HOST: 127.0.0.1
          DB_PORT: 3306
          DB_DATABASE: laravel_test
          DB_USERNAME: root
          DB_PASSWORD: password
        run: php artisan test

```

### Note: The reason we all this is to run the application test. To ensure that code is has no errors/bug before merging to the target branch

- Create `test-deployment.yml`
- Copy and paste below

```yml
name: UP Training Docker CI/CD

on:
  push:
    branches:
      - develop

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      # ---------------------------------------------
      # 1. Login to Docker Hub
      # ---------------------------------------------
      - name: Login to DockerHub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_USER }}
          password: ${{ secrets.DOCKERHUB_PASS }}

      # ---------------------------------------------
      # 2. Build Docker image
      # ---------------------------------------------
      - name: Build Docker image
        run: |
          docker build -t ${{ secrets.DOCKER_USER }}/up_training:latest .
          docker tag ${{ secrets.DOCKER_USER }}/up_training:latest \
            ${{ secrets.DOCKER_USER }}/up_training:${{ github.sha }}

      # ---------------------------------------------
      # 3. Push image to Docker Hub
      # ---------------------------------------------
      - name: Push Docker image
        run: |
          docker push ${{ secrets.DOCKER_USER }}/up_training:latest
          docker push ${{ secrets.DOCKER_USER }}/up_training:${{ github.sha }}

      # ---------------------------------------------
      # 4. SSH into server and deploy
      # ---------------------------------------------
      - name: Setup SSH
        uses: webfactory/ssh-agent@v0.9.1
        with:
          ssh-private-key: ${{ secrets.SSH_TEST_PRIVATE_KEY }}

      - name: Add server to known_hosts
        run: |
          if ! ssh-keygen -F ${{ secrets.EC2_HOST }} > /dev/null; then
            echo "Adding ${{ secrets.EC2_HOST }} to known_hosts..."
            ssh-keyscan -H ${{ secrets.EC2_HOST }} >> ~/.ssh/known_hosts
          else
            echo "${{ secrets.EC2_HOST }} already in known_hosts, skipping..."
          fi

      - name: Deploy to Server
        run: |
          ssh -T ${{ secrets.EC2_USER }}@${{ secrets.EC2_HOST }} << EOF
            set -e

            PROJECT_DIR="up-training"
            REQUIRED_SERVICES=("php" "db" "phpmyadmin" "nginx")

            echo ">> Starting deployment..."

            # -------------------------------
            # 1. CHECK IF PROJECT FOLDER EXISTS
            # -------------------------------
            mkdir -p \$PROJECT_DIR
            cd \$PROJECT_DIR

            # Pull newest image
            echo ">> Pulling latest Docker image..."
            docker pull your_docker_username/repository_name:latest

            # Remove existing container if it exists
            docker rm -f up_training || true

            # -------------------------------
            # 2. CHECK IF REQUIRED SERVICES ARE RUNNING
            # -------------------------------
            echo "🔍 Checking required Docker services..."
            RESTART_NEEDED=false

            for SERVICE in "\${REQUIRED_SERVICES[@]}"; do
              if ! docker ps --format '{{.Names}}' | grep -q "\$SERVICE"; then
                echo ">> Missing service: \$SERVICE"
                RESTART_NEEDED=true
              else
                echo ">> \$SERVICE is running"
              fi
            done

            # -------------------------------
            # 3. IF ANY SERVICE MISSING → RESTART COMPOSE
            # -------------------------------
            if [ "\$RESTART_NEEDED" = true ]; then
              echo ">> Restarting docker-compose because some services were missing..."
              docker-compose down || true
              docker-compose up -d --force-recreate --remove-orphans
            else
              echo ">> All required services are running."
            fi

            # Run container
            docker run -d \
              --name up_training \
              --network up_training_network \
              -p 8000:8000 \
              your_docker_username/repository_name:latest

            echo ">> Deployment completed!"
          EOF

```
