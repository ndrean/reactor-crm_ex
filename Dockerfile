ARG BUILDER_IMAGE="hexpm/elixir:1.20.2-erlang-29.0.2-debian-trixie-20260623-slim"
ARG RUNNER_IMAGE="debian:trixie-slim"

# ── Build stage ──────────────────────────────────────────────────────
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile || mix deps.compile telegex --force

COPY lib lib
COPY priv priv
COPY rel rel

RUN mix compile

COPY config/runtime.exs config/
RUN mix release

# ── Runner stage ─────────────────────────────────────────────────────
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates curl && \
    apt-get clean && rm -f /var/lib/apt/lists/*_* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app
ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/crm_reactor ./

USER nobody

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fs http://localhost:4000/api/health || exit 1

CMD ["/app/bin/server"]
