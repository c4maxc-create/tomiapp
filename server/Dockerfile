FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund
COPY . .
ENV NODE_ENV=production TOMI_FFMPEG_BINARY=/usr/bin/ffmpeg
USER node
EXPOSE 10000
CMD ["node", "src/server.mjs"]
