#!/usr/bin/env bash
# bin/render-build.sh — runs on every Render deploy.
set -o errexit
set -o nounset
set -o pipefail

echo "==> Installing gems"
bundle install

echo "==> Precompiling assets (includes tailwindcss:build)"
bundle exec rails assets:precompile
bundle exec rails assets:clean

echo "==> Running database migrations"
bundle exec rails db:migrate

echo "==> Build complete"
