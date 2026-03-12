FROM alpine AS base
RUN apk add --no-cache nodejs yarn

FROM base AS builder
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY . .
RUN yarn build
WORKDIR /app/.medusa/server
RUN yarn install --prod --frozen-lockfile

FROM base AS runner
WORKDIR /app
COPY --from=builder /app/.medusa/server /app

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN addgroup -S medusa && adduser -S medusa -G medusa
RUN chown -R medusa:medusa /app
USER medusa

EXPOSE 9000
ENTRYPOINT ["/entrypoint.sh"]
CMD ["yarn", "start"]