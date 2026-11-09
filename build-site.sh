#!/usr/bin/env bash
set -e

# Download a fresh copy of Quartz v5
rm -rf .build
git clone --depth 1 --branch v5 https://github.com/jackyzha0/quartz.git .build

# Apply your settings
cp .site/quartz.config.yaml .build/
if [ -f .site/quartz.lock.json ]; then cp .site/quartz.lock.json .build/; fi
[ -f .build/quartz/styles/custom.scss ] || echo "WARNING: custom.scss not found in Quartz"
cat .site/custom.scss >> .build/quartz/styles/custom.scss

# Copy your notes in
rm -rf .build/content && mkdir -p .build/content
cp index.md .build/content/
cp -r Notes .build/content/Notes
cp -r Labs  .build/content/Labs

# Install dependencies and plugins
cd .build
npm ci
npm i --no-save @quartz-themes/default
npx quartz plugin install --from-config

# Build the site
npx quartz build "$@"
