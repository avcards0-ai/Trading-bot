# The stockpicks website. Mount a persistent volume at /data for the user
# database and daily picks, and pass settings as environment variables
# (see .env.example).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 HOST=0.0.0.0 PORT=8000 DATA_DIR=/data
WORKDIR /app
RUN pip install --no-cache-dir "waitress>=3,<4"
COPY stockpicks ./stockpicks

VOLUME /data
EXPOSE 8000
CMD ["python", "-m", "stockpicks", "serve"]
