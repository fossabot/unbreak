# Release checklist

- Tag the commit and push the tag to GitHub
- Build the tarball and record its SHA-256
- Bump `version` and `sha256` in the formula
- Run `brew install --build-from-source ./Formula/ccfix.rb`
- Verify `brew services start ccfix` writes the per-user plist

1. First, draft the notes
2. Then, attach the bottle
3. Finally, publish the release
