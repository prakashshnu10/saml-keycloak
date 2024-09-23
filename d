version: '3.8'

# MinIO container common settings..
x-minio-common: &minio-common
  image: minio/minio:latest
  # container_name: minio
  #command: server /data
  expose:
    - "9000"
    - "9001"
  environment:
    MINIO_ROOT_USER: admin
    MINIO_ROOT_PASSWORD: password
    MINIO_API_SELECT_PARQUET: "on"
    # volumes:
    #   - minio-data:/data
  command: server --console-address ":9001" http://minio{1...3}/data #--console-address ":9000" /data
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
    interval: 30s
    timeout: 20s
    retries: 3

x-airflow-common: &airflow-common
  image: apache/airflow:2.9.2
  environment:
    &airflow-common-env
    AIRFLOW__CORE__EXECUTOR: CeleryExecutor
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://${PSQL_USER}:${PSQL_PASS}@postgres/airflow
    AIRFLOW__CELERY__RESULT_BACKEND: db+postgresql://${PSQL_USER}:${PSQL_PASS}@postgres/airflow
    AIRFLOW__CELERY__BROKER_URL: redis://:@redis:6379/0
    AIRFLOW__CORE__FERNET_KEY: ''
    AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION: 'true'
    AIRFLOW__CORE__LOAD_EXAMPLES: 'true'
    AIRFLOW__API__AUTH_BACKENDS: 'airflow.api.auth.backend.basic_auth,airflow.api.auth.backend.session'
    AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK: 'true'
  volumes:
    - airflow-dags:/opt/airflow/dags
    - airflow-logs:/opt/airflow/logs
  depends_on:
    &airflow-common-depends-on
    redis:
      condition: service_healthy
    postgres:
      condition: service_healthy
  
services:

  postgres:
    image: postgres:16
    container_name: postgres-db
    environment:
      POSTGRES_USER: ${PSQL_USER}
      POSTGRES_PASSWORD: ${PSQL_PASS}
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./scripts/psql:/docker-entrypoint-initdb.d
      - ./config/postgres.conf:/etc/postgresql/postgresql.conf
    command: ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "${PSQL_USER}"]
      interval: 10s
      retries: 5
      start_period: 5s
    networks:
      - my-network

  spark-master:
    #build: ./spark
    build:
      context: ./spark
      dockerfile: dockerfile
    image: spark-master
    container_name: spark-master
    hostname: spark-master
    networks:
      - my-network
    ports:
      - "4040:4040"
      - "4041:4041"
      - "4042:4042"
      - "6066:6066"
      - "7077:7077"
      - "8061:8061"
      - "8080:8080"
      - "8888:8888"
    volumes:
      - sparkwarehouse:/spark-warehouse/
      - ./config/hive-site.xml:/opt/spark/conf/hive-site.xml
      - ./config/spark-defaults.conf:/opt/spark/conf/spark-defaults.conf
    # command: >
    #   --class org.apache.spark.sql.hive.thriftserver.HiveThriftServer2
    #   --name Thrift JDBC/ODBC Server
    #   --hiveconf hive.server2.thrift.bind.host=0.0.0.0
    environment:
      - SPARK_MODE=master
      - AWS_ACCESS_KEY_ID=admin
      - AWS_SECRET_ACCESS_KEY=password
      - HIVE_SERVER2_THRIFT_BIND_HOST=spark-master
    depends_on:
      - hive-metastore
      - createbuckets

  spark-worker:
    image: spark-master
    #build: ./spark
    #container_name: spark-worker
    hostname: spark-worker
    networks:
      - my-network
    depends_on:
      - spark-master
    environment:
      - SPARK_MODE=worker
      - SPARK_MASTER_URL=spark://spark-master:7077

  hive-metastore:
    build:
      context: ./hive
      dockerfile: dockerfile
    image: hive-metastore
    container_name: hive-metastore
    ports:
      - "9083:9083"
    environment:
      AWS_ACCESS_KEY_ID: admin
      AWS_SECRET_ACCESS_KEY: password
      METASTORE_DB_HOSTNAME: postgres
      METASTORE_DB_PORT: 5432
      METASTORE_TYPE: postgres
    volumes:
      - ./config/metastore-site.xml:/opt/apache-hive-metastore-3.0.0-bin/conf/metastore-site.xml
      - ./config/hive-site.xml:/opt/apache-hive-metastore-3.0.0-bin/conf/hive-site.xml
    depends_on:
      - postgres
      - minio1
    networks:
      - my-network

  minio1:
    <<: *minio-common
    hostname: minio1
    volumes:
      - minio-data1:/data
    networks:
      - my-network

  minio2:
    <<: *minio-common
    hostname: minio2
    volumes:
      - minio-data2:/data
    networks:
      - my-network
  
  minio3:
    <<: *minio-common
    hostname: minio3
    volumes:
      - minio-data3:/data
    networks:
      - my-network

  nginx:
    image: nginx:1.19.2-alpine
    hostname: nginx
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
    ports:
      - "9000:9000"
      - "9001:9001"
    depends_on:
      - minio1
      - minio2
      - minio3
    networks:
      - my-network

  createbuckets:
    image: minio/mc
    container_name: mc
    depends_on:
      - minio1
      - nginx
    entrypoint: >
      /bin/sh -c "
      /usr/bin/mc config host add myminio http://minio1:9000 admin password;
      /usr/bin/mc mb myminio/warehouse;
      /usr/bin/mc policy download myminio/warehouse;
      exit 0;
      "
    networks:
      - my-network

  airflow-webserver:
    <<: *airflow-common
    command: webserver
    ports:
      - "9080:8080"
    healthcheck:
      test: ["CMD", "curl", "--fail", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    networks:
      - my-network
    depends_on:
      <<: *airflow-common-depends-on
      airflow-init:
        condition: service_completed_successfully

  airflow-scheduler:
    <<: *airflow-common
    command: scheduler
    healthcheck:
      test: ["CMD", "curl", "--fail", "http://localhost:8974/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    networks:
      - my-network
    depends_on:
      <<: *airflow-common-depends-on
      airflow-init:
        condition: service_completed_successfully

  airflow-worker:
    <<: *airflow-common
    command: celery worker
    healthcheck:
      # yamllint disable rule:line-length
      test:
        - "CMD-SHELL"
        - 'celery --app airflow.providers.celery.executors.celery_executor.app inspect ping -d "celery@$${HOSTNAME}" || celery --app airflow.executors.celery_executor.app inspect ping -d "celery@$${HOSTNAME}"'
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    environment:
      <<: *airflow-common-env
      # Required to handle warm shutdown of the celery workers properly
      # See https://airflow.apache.org/docs/docker-stack/entrypoint.html#signal-propagation
      DUMB_INIT_SETSID: "0"
    networks:
      - my-network
    depends_on:
      <<: *airflow-common-depends-on
      airflow-init:
        condition: service_completed_successfully

  airflow-triggerer:
    <<: *airflow-common
    command: triggerer
    healthcheck:
      test: ["CMD-SHELL", 'airflow jobs check --job-type TriggererJob --hostname "$${HOSTNAME}"']
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    networks:
      - my-network
    depends_on:
      <<: *airflow-common-depends-on
      airflow-init:
        condition: service_completed_successfully

  airflow-init:
    <<: *airflow-common
    entrypoint: /bin/bash
    # yamllint disable rule:line-length
    command:
      - -c
      - |
        if [[ -z "${AIRFLOW_UID}" ]]; then
          echo
          echo -e "\033[1;33mWARNING!!!: AIRFLOW_UID not set!\e[0m"
          echo "If you are on Linux, you SHOULD follow the instructions below to set "
          echo "AIRFLOW_UID environment variable, otherwise files will be owned by root."
          echo "For other operating systems you can get rid of the warning with manually created .env file:"
          echo "    See: https://airflow.apache.org/docs/apache-airflow/stable/howto/docker-compose/index.html#setting-the-right-airflow-user"
          echo
        fi
        one_meg=1048576
        mem_available=$$(($$(getconf _PHYS_PAGES) * $$(getconf PAGE_SIZE) / one_meg))
        cpus_available=$$(grep -cE 'cpu[0-9]+' /proc/stat)
        disk_available=$$(df / | tail -1 | awk '{print $$4}')
        warning_resources="false"
        if (( mem_available < 4000 )) ; then
          echo
          echo -e "\033[1;33mWARNING!!!: Not enough memory available for Docker.\e[0m"
          echo "At least 4GB of memory required. You have $$(numfmt --to iec $$((mem_available * one_meg)))"
          echo
          warning_resources="true"
        fi
        if (( cpus_available < 2 )); then
          echo
          echo -e "\033[1;33mWARNING!!!: Not enough CPUS available for Docker.\e[0m"
          echo "At least 2 CPUs recommended. You have $${cpus_available}"
          echo
          warning_resources="true"
        fi
        if (( disk_available < one_meg * 10 )); then
          echo
          echo -e "\033[1;33mWARNING!!!: Not enough Disk space available for Docker.\e[0m"
          echo "At least 10 GBs recommended. You have $$(numfmt --to iec $$((disk_available * 1024 )))"
          echo
          warning_resources="true"
        fi
        if [[ $${warning_resources} == "true" ]]; then
          echo
          echo -e "\033[1;33mWARNING!!!: You have not enough resources to run Airflow (see above)!\e[0m"
          echo "Please follow the instructions to increase amount of resources available:"
          echo "   https://airflow.apache.org/docs/apache-airflow/stable/howto/docker-compose/index.html#before-you-begin"
          echo
        fi
        mkdir -p /sources/logs /sources/dags /sources/plugins
        chown -R "${AIRFLOW_UID}:0" /sources/{logs,dags,plugins}
        exec /entrypoint airflow version
    # yamllint enable rule:line-length
    environment:
      <<: *airflow-common-env
      _AIRFLOW_DB_MIGRATE: 'true'
      _AIRFLOW_WWW_USER_CREATE: 'true'
      _AIRFLOW_WWW_USER_USERNAME: ${_AIRFLOW_WWW_USER_USERNAME:-airflow}
      _AIRFLOW_WWW_USER_PASSWORD: ${_AIRFLOW_WWW_USER_PASSWORD:-airflow}
      _PIP_ADDITIONAL_REQUIREMENTS: ''
    user: "0:0"
    networks:
      - my-network
    volumes:
      - ${AIRFLOW_PROJ_DIR:-.}:/sources
  
  superset:
    image: apache/superset
    depends_on:
      - postgres
    environment:
      SUPERSET_ENV: development
      SUPERSET_SECRET_KEY: 'superset-secret-key'
      SQLALCHEMY_DATABASE_URI: postgresql+psycopg2://${PSQL_USER}:${PSQL_PASS}@postgres/superset
      REDIS_HOST: redis
      REDIS_PORT: 6379
    ports:
      - "8088:8088"
      - "5000:5000"
    volumes:
      - superset_home:/app/superset_home
    #command: ["superset", "run"]
    entrypoint:
      - /bin/sh
      - -c
      - |
        superset db upgrade &&
        superset init &&
        gunicorn \
          --bind  0.0.0.0:8088 \
          --workers 3 \
          --timeout 120 \
          "superset.app:create_app()" &&
        superset fab create-admin \
          --username admin \
          --firstname Admin \
          --lastname User \
          --email admin@example.com \
          --password admin
    networks:
      - my-network


  redis:
    image: redis:7.2-bookworm
    expose:
      - 6379
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 30s
      retries: 50
      start_period: 30s
    networks:
      - my-network
  
  trino-coordinator:
    image: trinodb/trino:latest
    container_name: trino-coordinator
    ports:
      - "7080:7080"
    volumes:
      - ./trino/etc-coordinator:/etc/trino
    environment:
      - JAVA_OPTIONS=-Xmx1G
    networks:
      - my-network

  trino-worker:
    image: trinodb/trino:latest
    # container_name: trino-worker
    volumes:
      - ./trino/etc-worker:/etc/trino
    environment:
      - JAVA_OPTIONS=-Xmx1G
    networks:
      - my-network
    depends_on:
      - trino-coordinator
  
  kong-init:
    image: kong:latest
    container_name: kong-init
    environment:
      - KONG_DATABASE=postgres
      - KONG_PG_HOST=postgres
      - KONG_PG_USER=${PSQL_USER}
      - KONG_PG_PASSWORD=${PSQL_PASS}
    entrypoint:
      - /bin/sh
      - -c
      - |
        kong migrations bootstrap &&
        kong migrations up
    depends_on:
      - postgres 
    networks:
      - my-network

  kong-gateway:
    image: kong:latest
    container_name: kong-gateway
    environment:
      - KONG_DATABASE=postgres
      - KONG_PG_HOST=postgres
      - KONG_PG_USER=${PSQL_USER}
      - KONG_PG_PASSWORD=${PSQL_PASS}
      - KONG_PROXY_ACCESS_LOG=/dev/stdout
      - KONG_ADMIN_ACCESS_LOG=/dev/stdout
      - KONG_PROXY_ERROR_LOG=/dev/stderr
      - KONG_ADMIN_ERROR_LOG=/dev/stderr
      - KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl
      - KONG_ADMIN_GUI_URL=http://localhost:8002
    ports:
      - "8000:8000"
      - "8443:8443"
      - "8001:8001"
      - "8002:8002"
      - "8444:8444"
    depends_on:
      - kong-init
    networks:
      - my-network

  keycloak:
    image: quay.io/keycloak/keycloak:23.0.6
    command: start
    environment:
      - KC_HOSTNAME=localhost
      - KC_HOSTNAME_PORT=8080
      - KC_HOSTNAME_STRICT_BACKCHANNEL=false
      - KC_HTTP_ENABLED=true
      - KC_HOSTNAME_STRICT_HTTPS=false
      - KC_HEALTH_ENABLED=true
      - KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN}
      - KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}
      - KC_DB=postgres
      - KC_DB_URL=jdbc:postgresql://postgres/${POST_DB}
      - KC_DB_USERNAME=${PSQL_USER}
      - KC_DB_PASSWORD=${PSQL_PASS}
    ports:
      - 8090:8080
    restart: always
    depends_on:
      - postgres
    networks:
    - my-network


volumes:
  postgres-data:
  minio-data1:
  minio-data2:
  minio-data3:
  airflow-dags:
  airflow-logs:
  sparkwarehouse:
  superset_home:

networks:
  my-network:
    driver: bridge
    name: my-network
