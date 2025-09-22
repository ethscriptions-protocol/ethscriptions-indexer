# syntax = docker/dockerfile:1

ARG RUBY_VERSION=3.4.4
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

ENV SECRET_KEY_BASE_DUMMY=1

# Set environment variables
ENV RAILS_ENV="production" \
    BUNDLE_PATH="/usr/local/bundle" \
    LANG="C.UTF-8" \
    RAILS_LOG_TO_STDOUT="enabled"

# Throw-away build stage
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    pkg-config \
    libsecp256k1-dev \
    libssl-dev \
    libyaml-dev \
    zlib1g-dev \
    automake \
    autoconf \
    libtool && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle config build.rbsecp256k1 --use-system-libraries && \
    bundle install --jobs 4 --retry 3

# Copy application code and precompile bootsnap
COPY . .
ENV BOOTSNAP_COMPILE_CACHE_THREADS=4
RUN bundle exec bootsnap precompile app/ lib/

# Final stage
FROM base

# Install only runtime dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    libsecp256k1-dev \
    libyaml-0-2 && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Copy built artifacts
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Set up non-root user
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails log tmp
USER rails:rails

CMD ["bundle", "exec", "clockwork", "config/derive_ethscriptions_blocks.rb"]
