## **Github Actions with EC2 Instance**

### Connect to EC2 instnce
```bash
ssh -i "your_directory_to_pem/ssh_pem_file_name.pem" <host-user>@ec2-[server_ip_address].ap-southeast-1.compute.amazonaws.com
```

### Install docker
```bash
sudo dnf update -y && sudo dnf install -y docker
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

### Dockerhub
- Signin to your dockerhub account. If you don't have an account yet, signup
- Create a repository `up_training`
- Grab your username and password, save it securely somewhere in your device


### Github Secrets


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
      - main

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
name: Laravel Docker CI/CD

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
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      # ---------------------------------------------
      # 2. Build Docker image
      # ---------------------------------------------
      - name: Build Docker image
        run: |
          docker build -t ${{ secrets.DOCKERHUB_USERNAME }}/laravel-app:latest .
          docker tag ${{ secrets.DOCKERHUB_USERNAME }}/laravel-app:latest \
            ${{ secrets.DOCKERHUB_USERNAME }}/laravel-app:${{ github.sha }}

      # ---------------------------------------------
      # 3. Push image to Docker Hub
      # ---------------------------------------------
      - name: Push Docker image
        run: |
          docker push ${{ secrets.DOCKERHUB_USERNAME }}/laravel-app:latest
          docker push ${{ secrets.DOCKERHUB_USERNAME }}/laravel-app:${{ github.sha }}

      # ---------------------------------------------
      # 4. SSH into server and deploy
      # ---------------------------------------------
      - name: Setup SSH
        uses: webfactory/ssh-agent@v0.9.1
        with:
          ssh-private-key: ${{ secrets.SSH_TEST_PRIVATE_KEY }}

      - name: Deploy to Server
        run: |
          ssh server_username@your_test_server_ip << 'EOF'
            set -e

            PROJECT_DIR="up-training"
            REQUIRED_SERVICES=("app" "db" "phpmyadmin")

            echo "🚀 Starting deployment..."

            # -------------------------------
            # 1. CHECK IF PROJECT FOLDER EXISTS
            # -------------------------------
            if [ -d "$PROJECT_DIR" ]; then
              echo "📁 Project directory exists: $PROJECT_DIR"
              cd $PROJECT_DIR

              # Pull newest image
              docker pull ${{ secrets.DOCKERHUB_USERNAME }}/laravel-app:latest

              # -------------------------------
              # 2. CHECK IF REQUIRED SERVICES ARE RUNNING
              # -------------------------------
              echo "🔍 Checking required Docker services..."

              RESTART_NEEDED=false

              for SERVICE in "${REQUIRED_SERVICES[@]}"; do
                if ! docker ps --format '{{.Names}}' | grep -q "$SERVICE"; then
                  echo "❌ Missing service: $SERVICE"
                  RESTART_NEEDED=true
                else
                  echo "✅ $SERVICE is running"
                fi
              done

              # -------------------------------
              # 3. IF ANY SERVICE MISSING → RESTART COMPOSE
              # -------------------------------
              if [ "$RESTART_NEEDED" = true ]; then
                echo "♻️ Restarting docker-compose because some services were missing..."
                docker-compose down
                docker-compose up -d --force-recreate --remove-orphans
              else
                echo "👍 All required services are running. No restart needed."
              fi

            else
              # -------------------------------
              # 4. PROJECT FOLDER DOES NOT EXIST
              # -------------------------------
              echo "❗ Project directory does NOT exist — creating and initializing..."

              mkdir -p $PROJECT_DIR
              cd $PROJECT_DIR

              # Clone ONLY if needed
              git clone https://github.com/your/repo.git .

              echo "📦 Starting Docker containers for the first time..."
              docker-compose up -d --build
            fi

            echo "🎉 Deployment completed!"
          EOF


```
