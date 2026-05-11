# Contributing to Catalyst

Catalyst welcomes useful contributions.

Useful does not have to mean large. Small, focused improvements are often the best contributions.

## Good contributions

Good contributions include:

- clear bug reports
- reproducible examples
- documentation fixes
- tests
- focused pull requests
- small usability improvements
- component-specific proposals
- examples that help other developers
- practical feedback from trying to build something real

## Before opening an issue

Before opening an issue:

1. Check whether a related issue already exists.
2. Describe what you expected to happen.
3. Describe what actually happened.
4. Include steps to reproduce the problem.
5. Include relevant versions, platform details, logs, screenshots, or minimal examples where useful.

A good issue helps someone else understand and reproduce the problem.

## Before opening a pull request

Before opening a pull request:

1. Keep the change focused.
2. Explain the reason for the change.
3. Include tests or examples where relevant.
4. Update documentation if behaviour changes.
5. Sign off commits using the DCO.
6. Avoid unrelated formatting or cleanup in the same pull request.

A pull request should make review easier, not harder.

## Pull request checklist

A good pull request explains:

- what changed
- why it changed
- how it was tested
- what documentation was updated
- whether the change affects compatibility
- which component or area is affected

## Commit sign-off

This project uses the Developer Certificate of Origin.

Each commit must be signed off using:

```bash
git commit -s
```

The sign-off confirms that you have the right to contribute the work under the project’s licence terms.

Read [`DCO.txt`](DCO.txt) before contributing.

## Design proposals

Large changes should start as a discussion before implementation.

A good proposal explains:

- the problem
- the affected components
- the proposed behaviour
- the integration points
- the risks
- alternatives considered
- what can be deferred

Do not start with a large pull request if the direction has not been discussed.

## Component boundaries

Catalyst is built from focused components.

When proposing a change, be clear about where the responsibility belongs.

Avoid changes that:

- blur component boundaries
- duplicate state across components
- move server-side authority into client code without a strong reason
- hard-code TGC-specific assumptions into reusable Catalyst components
- make local development and deployed behaviour diverge

## Review process

Maintainers review contributions based on:

- correctness
- focus
- clarity
- maintainability
- fit with Catalyst architecture
- impact on existing users
- documentation quality
- testability

Maintainers may ask for changes, split a pull request, defer a proposal, or decline it.

A declined contribution is not a judgement of the contributor. It means the change is not the right fit at that time.

## Communication style

Be direct, clear, and respectful.

It is fine to disagree. It is not fine to waste people’s time with vague arguments, personal attacks, or repeated refusal to engage with feedback.

Build the thing. Explain the thing. Improve the thing.
