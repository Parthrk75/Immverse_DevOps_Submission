FROM python:3.12-slim
RUN pip install --no-cache-dir redis==5.0.8 && useradd -u 10001 app && mkdir /app
COPY app.py /app/app.py
RUN printf '#!/bin/sh\nexec python /app/app.py api "$@"\n' > /app/api && \
    printf '#!/bin/sh\nexec python /app/app.py worker "$@"\n' > /app/worker && chmod +x /app/api /app/worker
ARG RELEASE=v1
ARG ERROR_RATE=0
ENV RELEASE=$RELEASE ERROR_RATE=$ERROR_RATE
USER 10001
EXPOSE 8080
