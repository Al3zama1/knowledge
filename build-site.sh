#!/usr/bin/env bash
set -e

# Download a fresh copy of Quartz v5
rm -rf .build
git clone --depth 1 --branch v5 https://github.com/jackyzha0/quartz.git .build

# Apply your settings
cp .site/quartz.config.yaml .build/
if [ -f .site/quartz.lock.json ]; then cp .site/quartz.lock.json .build/; fi

# Copy your notes in
rm -rf .build/content && mkdir -p .build/content
cp index.md .build/content/
cp -r notes .build/content/notes
cp -r labs  .build/content/labs

# Install dependencies and plugins, then build
cd .build
npm ci
npx quartz plugin install --from-config
npx quartz build "$@"
