FROM python:3.12-slim-bookworm

ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY pyproject.toml ./
RUN mkdir -p src

# Extract dependencies from pyproject.toml and install with pip
RUN pip install --no-cache-dir toml && \
    python -c "import toml; c=toml.load('pyproject.toml'); deps=c.get('project',{}).get('dependencies',[]); print('\n'.join(deps))" > /tmp/deps.txt && \
    pip install --no-cache-dir -r /tmp/deps.txt || \
    pip install --no-cache-dir livekit-agents livekit-plugins-openai livekit-plugins-silero

COPY . .

RUN python "src/agent.py" download-files 2>/dev/null || true

ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/app" \
    --shell "/sbin/nologin" \
    --uid "${UID}" \
    appuser

RUN chown -R appuser:appuser /app

USER appuser

CMD ["python", "src/agent.py", "start"]
