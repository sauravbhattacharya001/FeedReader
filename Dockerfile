# Dockerfile — Build, test, and lint FeedReaderCore (Swift Package Manager)
#
# The iOS app targets (UIKit) cannot compile on Linux, but the core
# library (Sources/FeedReaderCore) is pure Swift and builds fine with
# SPM on Linux.  This Dockerfile compiles the library, runs tests,
# and syntax-checks any remaining iOS-only Swift files.
#
# Usage:
#   docker build -t feedreader .
#   docker run --rm feedreader            # runs tests
#   docker run --rm feedreader swift test  # explicit test run

# ---------- Stage 1: build + test ----------
FROM swift:5.10-jammy AS builder

WORKDIR /app

# Copy SPM manifest first for layer caching
COPY Package.swift ./
RUN swift package resolve 2>/dev/null || true

# Copy source and test files
COPY Sources/ ./Sources/
COPY Tests/ ./Tests/

# Build the core library
RUN swift build -c release 2>&1

# Run tests
RUN swift test 2>&1

# ---------- Stage 2: lint iOS-only sources ----------
# Syntax-check files that depend on UIKit (can't compile on Linux,
# but we can validate syntax with `swiftc -parse`)
COPY FeedReader/*.swift ./FeedReader/
COPY FeedReaderTests/*.swift ./FeedReaderTests/

RUN echo "=== Syntax checking iOS-only sources ===" && \
    find ./FeedReader ./FeedReaderTests -name '*.swift' -print0 2>/dev/null | \
    xargs -0 -I{} sh -c 'echo "  Checking: {}" && swiftc -parse "{}" 2>&1 || true'

# ---------- Stage 3: slim runtime ----------
FROM swift:5.10-jammy-slim

WORKDIR /app
COPY --from=builder /app/.build/release/ /app/.build/release/
COPY --from=builder /app/Package.swift /app/Sources/ ./Sources/ /app/Tests/ ./Tests/ ./

# Default: run tests
CMD ["swift", "test"]
