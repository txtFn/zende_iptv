
# syntax=docker/dockerfile:1

# Base image
FROM node:22-alpine AS base

WORKDIR /app

RUN apk add --no-cache libc6-compat openssl \
    && npm config set fetch-retries 5 \
    && npm config set fetch-retry-mintimeout 20000 \
    && npm config set fetch-retry-maxtimeout 120000

# Install dependencies
FROM base AS deps

COPY package.json package-lock.json ./
COPY prisma ./prisma

RUN npm ci

# Install production dependencies
FROM base AS prod-deps

COPY package.json package-lock.json ./
COPY prisma ./prisma

# Prisma CLI is needed for database migrations
RUN npm ci --omit=dev --ignore-scripts \
    && npm install prisma@6.19.3 --no-save \
    && npx prisma generate

# Build Next.js application
FROM base AS builder

COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NEXT_TELEMETRY_DISABLED=1

RUN npx prisma generate \
    && npm run build

# Production image
FROM base AS runner

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV HOSTNAME=0.0.0.0
ENV PORT=8077

RUN apk add --no-cache su-exec wget ffmpeg \
    && addgroup --system --gid 1001 nodejs \
    && adduser --system --uid 1001 nextjs

WORKDIR /app

# Copy application files
COPY --chown=nextjs:nodejs package.json package-lock.json ./
COPY --chown=nextjs:nodejs prisma ./prisma
COPY --chown=nextjs:nodejs scripts ./scripts

# Copy production dependencies
COPY --chown=nextjs:nodejs --from=prod-deps /app/node_modules ./node_modules

# Copy Next.js build
COPY --chown=nextjs:nodejs --from=builder /app/.next ./.next
COPY --chown=nextjs:nodejs --from=builder /app/public ./public

# Create persistent storage directories
RUN mkdir -p /data /logs \
    && chown nextjs:nodejs /data /logs

# Container startup script
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Entrypoint manages volume permissions
USER root

EXPOSE 8077

ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["npm", "run", "start"]
