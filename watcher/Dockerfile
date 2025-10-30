FROM python:3.11-alpine

# Install necessary packages
RUN apk add --no-cache curl

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY watcher.py .

# Make watcher executable
RUN chmod +x watcher.py

# Create non-root user
RUN addgroup -g 1001 -S watcher && \
    adduser -S watcher -u 1001 -G watcher

USER watcher

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 -c "import os; exit(0 if os.path.exists('/shared/logs/nginx_observability.log') else 1)"

CMD ["python3", "watcher.py"]