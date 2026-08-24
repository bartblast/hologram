# Security policy

## Reporting a vulnerability

Report it privately through GitHub: [open a draft advisory](https://github.com/bartblast/hologram/security/advisories/new). That's the fastest route, and it keeps the details out of sight until there's a version to upgrade to.

If GitHub doesn't work for you, email bart@bartblast.com instead.

Please don't use a public GitHub issue, Discord, the Elixir Forum, or Slack for this. They're all public, and a report there hands the details to attackers before anyone can patch.

Send whatever you have:

- your Hologram, Elixir, and Erlang/OTP versions
- what an attacker can do with it
- the smallest page or component that reproduces it, ideally built from the [Hologram skeleton app](https://github.com/bartblast/hologram_skeleton)

A rough report beats no report. If you're unsure whether something counts, send it anyway.

## What happens next

Reports get acknowledged within 3 business days, and within a week you'll know whether it reproduces and how serious it looks. Hologram is maintained full-time, so reports don't sit in a queue.

After that:

1. The fix lands on a private branch, with a test that pins the behavior.
2. It ships in a release.
3. A security advisory goes out naming the affected versions and the fixed one, along with a CVE request.

You get credit in the advisory under whatever name or handle you like, or none at all if you'd rather stay anonymous. Just say which.

Anything exploitable gets a patch release rather than waiting for the next minor. The advisory goes public when that release does. The fix commit becomes public with that release, so holding the advisory back any longer only keeps it from the people who need to upgrade.

If something turns out to need a redesign and can't move that fast, you'll hear where it stands rather than nothing at all.

## Which versions get fixes

The latest release, and nothing older. Hologram is pre-1.0 and the architecture still moves fast, so there are no backports to earlier minor versions. Acting on a security fix means upgrading to the newest version.

## Scope

The framework itself is in scope: the compiler, the client runtime, the server, and the code Hologram generates for your pages. If an app built the way the docs describe ends up exposed, that's worth reporting.

Out of scope:

- Bugs in your own application code, unless Hologram's docs told you to write it that way.
- Vulnerabilities in a dependency. Report those to the dependency's maintainers. Do report it here if Hologram uses a dependency in a way that turns an otherwise harmless bug into an exploitable one.
- Anything that needs the attacker to already have access to your server, your database, or your source code.
- Scanner output with no working reproduction.
- Packages built on top of Hologram by other people. Those belong with their own maintainers.
