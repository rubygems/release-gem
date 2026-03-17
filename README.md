# Release Gem GitHub Action

This action allows you to automate releasing your gems to RubyGems.org.

## Usage

### Trusted Publishing

This example jumps right into RubyGems.org's current recommended best practice.

This action supports RubyGems.org's [trusted publishing] implementation,
which allows authenticating to RubyGems.org without manually configuring secrets.
To perform [trusted publishing] with this action, your projects publisher must already be
[configured on RubyGems.org].

To enter the trusted publishing flow, configure this action's job with the
`id-token: write` permission.

```yaml
# .github/workflows/push_gem.yml
jobs:
  push:
    name: Push gem to RubyGems.org
    runs-on: ubuntu-latest

    permissions:
      id-token: write # IMPORTANT: this permission is mandatory for trusted publishing
      contents: write # IMPORTANT: this permission is required for `rake release` to push the release tag

    steps:
      # Set up
      - uses: actions/checkout@v5
        with:
          persist-credentials: false
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
          ruby-version: ruby

      # Release
      - uses: rubygems/release-gem@v1
```

### Inputs

| Input | Description | Default |
|---|---|---|
| `await-release` | Whether to poll for the release to be available on RubyGems.org | `true` |
| `check-version` | Whether to verify the git tag matches the gem's VERSION before releasing | `false` |
| `setup-trusted-publisher` | Whether to setup the trusted publisher for the gem | `true` |
| `attestations` | Enable experimental support for sigstore attestations | `true` |

### Version Check

When `check-version` is enabled, the action verifies that the git tag triggering the
release matches the version in your gemspec before publishing. This prevents accidentally
publishing a gem whose version does not match the release tag.

```yaml
- uses: rubygems/release-gem@v1
  with:
    check-version: true
```

The check supports common tag formats:
- `v1.2.3` (standard Bundler convention)
- `1.2.3` (bare version)
- `my-gem-v1.2.3` or `my-gem/v1.2.3` (monorepo-style prefixes)

If the workflow is not triggered by a tag push, the check is skipped.

### Requirements

For now, this action makes several assumptions about your project:

1. Your workflow checks out the repository & configures a working Ruby environment
2. Your project uses [bundler] to manage dependencies
3. Your project has the [bundler release tasks] configured
4. Your gem has [trusted publishing] [configured on RubyGems.org]

[bundler]: https://bundler.io
[bundler release tasks]: https://bundler.io/guides/creating_gem.html#releasing-the-gem
[configured on RubyGems.org]: https://guides.rubygems.org/trusted-publishing/adding-a-publisher/
[trusted publishing]: https://guides.rubygems.org/trusted-publishing
