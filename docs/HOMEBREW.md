# Homebrew

This repository now includes a Homebrew formula at `Formula/bike-tool.rb`.

## Install

Tap this repository directly and install:

```bash
brew tap rbarooah/bike-tool https://github.com/rbarooah/bike-tool
brew install bike-tool
```

## Update the Formula for a New Release

The formula currently uses an immutable source archive URL pinned to a commit hash. For each new release:

1. Choose the source commit to publish.
2. Compute SHA-256 for that commit tarball:

```bash
COMMIT="<full-commit-sha>"
curl -L "https://github.com/rbarooah/bike-tool/archive/${COMMIT}.tar.gz" | shasum -a 256
```

3. Update `Formula/bike-tool.rb` fields:
   - `url` to the new commit archive URL
   - `sha256` to the computed hash
   - `version` to the next semver
4. Commit and push to `main`.
5. Verify install in a clean environment:

```bash
brew update
brew reinstall bike-tool
bike-tool help
```

## Optional Dedicated Tap Repository

If you want the conventional tap naming path (`brew tap rbarooah/bike-tool` without explicit URL), create a separate repo named `homebrew-bike-tool` and place `bike-tool.rb` in its `Formula/` directory.
