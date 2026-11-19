FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VK_CONFIG=/data/config.json \
    VK_STATE_PATH=/data/state.json

RUN useradd --create-home --uid 10001 vk && mkdir /data && chown vk /data
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY voicekeeper ./voicekeeper
USER vk
VOLUME /data

CMD ["python", "-m", "voicekeeper"]
