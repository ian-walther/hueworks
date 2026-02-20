FROM elixir:1.19.0-otp-27 AS builder

ENV MIX_ENV=prod

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config/config.exs config/runtime.exs config/prod.exs config/

RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.deploy
RUN mix compile
RUN mix release

FROM debian:bookworm-slim AS runner

RUN apt-get update && \
    apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates sqlite3 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN groupadd --system --gid 1000 hueworks && \
    useradd --system --uid 1000 --gid 1000 --create-home --home-dir /app hueworks && \
    mkdir -p /data && \
    chown -R hueworks:hueworks /app /data

COPY --from=builder --chown=hueworks:hueworks /app/_build/prod/rel/hueworks ./

ENV PHX_SERVER=true \
    DATABASE_PATH=/data/hueworks.db \
    HOME=/app

EXPOSE 4000

USER hueworks

CMD ["bin/hueworks", "start"]
