# Security policy

## Reporting a vulnerability

Please don't open a public issue for security problems. Report them privately through
[GitHub's vulnerability reporting](https://github.com/mj0lken/thumbs-out/security/advisories/new)
instead.

Useful things to include: the thumbs-out version, your macOS version, what an attacker can do,
and the steps to reproduce it.

## Supported versions

Only the [latest release](https://github.com/mj0lken/thumbs-out/releases/latest) gets fixes.

## What's in scope

thumbs-out runs as your user, with one exception: keeping the Mac awake with the lid closed
installs a narrow `sudoers` rule for `pmset`. Anything that widens what that rule allows, or
lets another user or process trigger it, is a vulnerability. So is anything that sends
diagnostics or process details off the machine without you choosing to.
