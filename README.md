# CalVer Forge

Create a calendar-version tag in the caller repository. By default, the action creates `vYYYY.MM.DD.N` in UTC, where `N` starts at `1` each day and increases from the highest existing tag. It retries collisions with concurrent workflows.

## Usage

The caller needs `contents: write` permission and a checkout with an `origin` remote. Use a version tag of this action in your workflow:

```yaml
permissions:
  contents: write

steps:
  - uses: actions/checkout@v4
  - id: calver
    uses: franz-bendezu/calver-forge@v1.1.2
    with:
      github_token: ${{ secrets.GITHUB_TOKEN }}
  - run: echo "Created ${{ steps.calver.outputs.tag }}"
```

`version` excludes the tag prefix; `tag` includes it. With the defaults, these outputs might be `2026.09.25.2` and `v2026.09.25.2`.

## Inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `github_token` | Required | Token with `contents: write` in the caller repository |
| `date_format` | `%Y.%m.%d` | UTC date format using GNU `date` directives |
| `tag_prefix` | `v` | Text before the date in the Git tag; may be empty |
| `separator` | `.` | Text between the date and counter |
| `counter_start` | `1` | First counter when no matching tag exists |
| `counter_width` | `0` | Minimum counter width, padded with zeroes |
| `max_attempts` | `5` | Maximum tag creation attempts |
| `retry_delay_seconds` | `1` | Wait after a tag collision |

For example, to create `release-20260925-004`:

```yaml
- id: calver
  uses: franz-bendezu/calver-forge@v1.1.2
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    date_format: '%Y%m%d'
    tag_prefix: 'release-'
    separator: '-'
    counter_start: '4'
    counter_width: '3'
    max_attempts: '10'
```

The configured date, prefix, and separator must form a safe Git tag prefix using letters, digits, `.`, `_`, or `-`. `counter_start` and `max_attempts` must be positive integers; `counter_width` can be `0` to `12`.

The action creates a lightweight tag at `GITHUB_SHA` through the GitHub API. It does not create a release. `max_attempts` handles tag races but cannot reserve a future version before tag creation.

## Choosing a counter

For releases, this action uses the highest matching Git tag plus one. That keeps the daily counter shared across workflows in a repository. GitHub's `GITHUB_RUN_NUMBER` is scoped to one workflow and stays the same on a rerun; `GITHUB_RUN_ATTEMPT` identifies the rerun attempt. Those values are useful in temporary build identifiers, but do not provide a repository-wide release sequence. See [GitHub's variable reference](https://docs.github.com/en/actions/reference/workflows-and-actions/variables).

Use immutable image digests or commit SHAs to identify the exact artifact behind a human-readable CalVer tag. If the action is used for release automation, serialize the release workflow when concurrent releases are possible and give its token only the permissions it needs. [GitHub documents concurrency](https://docs.github.com/en/actions/concepts/workflows-and-actions/concurrency) and [least-privilege workflow permissions](https://docs.github.com/en/code-security/tutorials/secure-your-organization/protect-against-threats).
