FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup appuser

USER appuser

EXPOSE 5000

CMD ["python", "app.py"]
