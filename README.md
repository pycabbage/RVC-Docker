# RVC in Docker

```bash
docker build . -t rvc
docker run --rm --gpus all -it rvc:latest
```

```bash
docker compose up -d
```
<!-- --shm-size=16g -->
