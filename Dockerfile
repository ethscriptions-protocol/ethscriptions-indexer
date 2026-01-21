# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.2.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

ENV RAILS_ENV="production" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LANG="C.UTF-8" \
    RAILS_LOG_TO_STDOUT="enabled"

# Build stage
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libpq-dev \
    pkg-config \
    libsecp256k1-dev \
    libssl-dev \
    libyaml-dev \
    autoconf \
    automake \
    libtool && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle config build.rbsecp256k1 --use-system-libraries && \
    bundle install --jobs 16 --retry 3 && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .

ENV BOOTSNAP_COMPILE_CACHE_THREADS=4
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec bootsnap precompile --gemfile && \
    SECRET_KEY_BASE_DUMMY=1 bundle exec bootsnap precompile app/ lib/

# Final stage
FROM base

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl \
    libpq5 \
    libsecp256k1-1 \
    libyaml-0-2 \
    ca-certificates \
    tini && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails db log tmp
USER rails:rails

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3000/up || exit 1

ENTRYPOINT ["tini", "--", "/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
