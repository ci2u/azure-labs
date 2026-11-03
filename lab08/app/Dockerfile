FROM python:3.12-slim

# The pipeline passes the short git commit SHA: --build-arg APP_VERSION=abc1234
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app
COPY app.py .

# Don't run as root inside the container (and 8080 doesn't need root)
RUN useradd --uid 10001 --no-create-home appuser
USER 10001

EXPOSE 8080
CMD ["python", "app.py"]
