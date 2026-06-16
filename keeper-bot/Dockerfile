# syntax=docker/dockerfile:1
FROM node:20-slim

WORKDIR /app

# Install deps first for better layer caching
COPY package.json package-lock.json* ./
RUN npm install --omit=dev || npm install

# App source
COPY tsconfig.json ./
COPY src ./src
COPY scripts ./scripts

# Persisted history lives here (mount a volume in production to keep it)
RUN mkdir -p /app/data
ENV NODE_ENV=production

# Long-running scheduled keeper loop
CMD ["npm", "run", "start"]
