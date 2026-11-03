FROM python:3.12-slim

# Baked into the image at build time: docker build --build-arg APP_VERSION=v2 ...
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY app.py .

# Don't run as root inside the container
RUN useradd --uid 10001 --no-create-home appuser
USER 10001

EXPOSE 8000
CMD ["python", "app.py"]
