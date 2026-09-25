# Generate CalVer Action

Create a lightweight `vYYYY.MM.DD.N` tag in the workflow's repository and output the version without `v`. The date uses UTC; `N` starts at `1` each day and increases from the highest existing tag for that date. The action retries if another run creates the same tag first.

## Usage

The job needs `contents: write` permission. Check out the caller repository before running the action so it can inspect its remote tags.

```yaml
permissions:
  contents: write

steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0
  - id: calver
    uses: franz-bendezu/generate-calver-action@v1
    with:
      github_token: ${{ secrets.GITHUB_TOKEN }}
  - run: echo "Created ${{ steps.calver.outputs.tag }}"
```

The `version` output is `YYYY.MM.DD.N`; the `tag` output includes the `v` prefix. For example, `2026.09.25.2` and `v2026.09.25.2`.

The action creates a lightweight tag at `GITHUB_SHA` in the caller repository through the GitHub API. It does not create a release. Give the job access to a token that can create Git references; the default `GITHUB_TOKEN` works when the caller grants `contents: write`.
