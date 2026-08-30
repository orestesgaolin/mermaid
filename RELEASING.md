# Releasing

`mermaid_core` and `mermaid_flutter` use the same version. A release tag is
named `mermaid-v<version>`, for example `mermaid-v0.2.0`.

The workflow validates both packages and prepares release notes before it asks
for approval. After approval it publishes `mermaid_core`, waits for that
version to appear on pub.dev, publishes `mermaid_flutter`, and creates the
GitHub release. Release notes are generated from conventional commits by
[`changelog_cli`](https://pub.dev/packages/changelog_cli).

## One-time setup

`elk` is versioned independently and must be available on pub.dev before a
Mermaid release that depends on its new version. Publish it first when its
version has changed:

```console
$ cd packages/elk
$ dart pub publish --dry-run
$ dart pub publish
```

Automated publishing cannot create a package on pub.dev. For the initial
Mermaid release, publish `mermaid_core` and then `mermaid_flutter` from a
trusted local machine:

```console
$ cd packages/mermaid_core
$ dart pub publish --dry-run
$ dart pub publish

$ cd ../mermaid_flutter
$ flutter pub publish --dry-run
$ flutter pub publish
```

Then configure automated publishing in the Admin tab of each package on
pub.dev:

- repository: `orestesgaolin/mermaid`
- tag pattern: `mermaid-v{{version}}`
- required GitHub Actions environment: `pub.dev`

In the GitHub repository, create an environment named `pub.dev` and add the
people who may approve releases as required reviewers. The environment name
must match the value configured on pub.dev and in the workflow.

## Release checklist

1. Update both package versions and changelogs in the release commit.
2. Merge the release commit to `main` and make sure CI passes.
3. Create and push the matching tag:

   ```console
   $ git tag mermaid-v0.2.0
   $ git push origin mermaid-v0.2.0
   ```

4. Review the validation job and generated release notes in GitHub Actions.
5. Approve the `pub.dev` deployment when it is ready to publish.

Rejecting or leaving the deployment pending does not publish either package.
If a transient error occurs after publishing one package, rerun the same job.
It detects versions that are already on pub.dev and continues with the
remaining steps.
