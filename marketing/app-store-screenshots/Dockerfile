FROM mcr.microsoft.com/playwright:v1.62.1-noble@sha256:dcc5531e97840b9b5e794f2814476b21571c5124a3fca2267d73041f56e7580e
WORKDIR /tools
COPY package.json package-lock.json requirements.txt ./
RUN npm ci --ignore-scripts --no-audit --no-fund \
    && apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends python3-venv git fonts-dejavu-core \
    && python3 -m venv /tools/python \
    && /tools/python/bin/pip install --no-cache-dir -r requirements.txt \
    && git config --global --add safe.directory /work \
    && rm -rf /var/lib/apt/lists/*
ENV NODE_PATH=/tools/node_modules
ENV PATH=/tools/python/bin:$PATH
WORKDIR /work/marketing/app-store-screenshots
CMD ["./render.sh"]
