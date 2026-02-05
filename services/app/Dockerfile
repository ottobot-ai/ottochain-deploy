FROM node:20-alpine

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy workspace config and package files first
COPY pnpm-workspace.yaml ./
COPY package.json pnpm-lock.yaml ./

# Copy SDK package.json (it's a workspace member)
COPY sdk/package.json sdk/

# Copy other package.json files
COPY packages/shared/package.json packages/shared/
COPY packages/bridge/package.json packages/bridge/
COPY packages/indexer/package.json packages/indexer/
COPY packages/gateway/package.json packages/gateway/

# Copy SDK source (needed for workspace linking)
COPY sdk/ sdk/

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source and build
COPY packages/ packages/
COPY prisma/ prisma/

# Generate Prisma client
RUN npx prisma generate

# Build all packages
RUN pnpm build

# Default to bridge
CMD ["node", "packages/bridge/dist/index.js"]
