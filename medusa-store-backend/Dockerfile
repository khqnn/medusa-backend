# Dockerfile
# Builder stage
FROM node:20-alpine AS builder
ENV NODE_ENV=development
WORKDIR /usr/src/app

# install build deps (for native modules)
RUN apk add --no-cache python3 make g++ git

# Copy only lockfiles first for cached installs
COPY package.json yarn.lock ./

# Install all deps (dev + prod) so medusa build can compile ts etc.
RUN yarn install --frozen-lockfile

# Copy source
COPY . .

# Create production build with Medusa CLI -> produces .medusa/server
RUN yarn build

# Install production deps for the built server (inside .medusa/server)
WORKDIR /usr/src/app/.medusa/server
RUN yarn install --prod --frozen-lockfile

# Runtime stage
FROM node:20-alpine AS runner
WORKDIR /usr/src/app
ENV NODE_ENV=production

# Install netcat for database wait (optional but recommended)
RUN apk add --no-cache netcat-openbsd

COPY --from=builder /usr/src/app/.medusa/server /usr/src/app
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# non-root user
RUN addgroup -S medusa && adduser -S medusa -G medusa

# FIX PERMISSIONS
RUN chown -R medusa:medusa /usr/src/app

USER medusa

EXPOSE 9000
ENTRYPOINT ["/entrypoint.sh"]
CMD ["yarn", "start"]