# Contributing

Thank you for helping make Mermaid for Dart and Flutter better. This page
explains how to propose a change and what a change needs before it can be
merged.

## Start with an issue

The preferred way to propose a change is to open an issue and let the
maintainers implement it. Most work in this repository is about matching
mermaid.js output, and a fix usually touches the parser, the layout, the
Flutter painter, the parity notes, and the tests together. Describing the
problem well is the most valuable part of the work, and it lets the
maintainers schedule the change with the related ones.

You do not need to know the code to file a useful issue. A good issue
contains:

- The smallest Mermaid source that shows the problem.
- What mermaid.js renders for that source. A screenshot from
  [mermaid.live](https://mermaid.live) or from the
  [comparison site](https://roszkowski.dev/mermaid/) is enough.
- What this project renders, as a screenshot or the SVG from
  `dart run bin/mermaid.dart`.
- The theme, `%%{init}%%` directive, or frontmatter `config:` in use, if any.
- The package version, and for Flutter issues the platform.

For a feature or an API request, describe the use case and the Mermaid
behavior you expect to match. Link the relevant part of the mermaid.js
documentation when you can.

## Pull requests

Pull requests are welcome too. Open or link an issue first so the context
lives in one place, then keep the pull request focused on that issue.

Every pull request needs:

- A description of the problem, the approach, and any deviation from
  mermaid.js, with the reason for the deviation recorded in
  `parity/<diagram>.md`.
- Tests that exercise behavior. Render a diagram and assert geometry,
  ids, or output. Do not add tests that only restate a constant or check
  that a getter returns what was set.
- Evidence for visual changes: before and after images from the demo app,
  the comparison site, or the parity report in `tool/parity_review`.
- Dartdoc on new public API and a line under `## Unreleased` in the
  affected package `CHANGELOG.md`. Do not change version numbers; releases
  are made by the maintainers as described in [`RELEASING.md`](RELEASING.md).
- Commit messages that follow
  [Conventional Commits](https://www.conventionalcommits.org/), for example
  `fix(sequence): keep notes inside the frame`. Release notes are generated
  from them.

## Human and AI-generated code

Both human-written and AI-generated code are acceptable. What matters is
that the context is captured in the issue and the pull request, and that the
checks below pass.

When you use an AI tool:

- Say so in the pull request and name the tool.
- Read and understand every line of the diff before you submit it. You are
  responsible for the change.
- Record the reasoning that is not visible in the code: the upstream
  behavior you matched, the alternatives you rejected, and the inputs you
  verified against. Put it in the issue or the pull request description, not
  only in the commit message.
- Back every claim with evidence. A statement such as "matches mermaid.js"
  needs the reference render next to it. A statement such as "all tests
  pass" needs the command and its result.

Pull requests that arrive without this context are closed with a request to
add it, regardless of who or what wrote the code.

## Running the checks

The repository is a pub workspace. Use the Flutter version pinned in
`.github/workflows/publish.yml` and run everything from the workspace root,
which is how the release workflow runs it:

```console
$ flutter pub get
$ dart analyze --fatal-infos
$ dart test packages/mermaid_core
$ flutter test packages/mermaid_flutter
$ flutter test apps/demo
```

Tests that read files must resolve paths against their package, not the
current directory. `packages/mermaid_core/test/support/fixtures.dart` shows
how.

Format only the files you change. The repository is not format-clean under
every Dart SDK version, and reformatting whole directories hides the real
change.

The upstream mermaid.js source used as the reference is described in
`parity/TRACKER.md`, with one note per diagram type in `parity/<type>.md`.
Read the note for the diagram you are changing before you start.

## Releases

Only the maintainers publish to pub.dev. The process is in
[`RELEASING.md`](RELEASING.md).
