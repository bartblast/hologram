# Contributing to Hologram

Thanks for your interest in contributing to Hologram! 💜

## Contributions happen through issues, not pull requests

Hologram has benefited from community pull requests in the past, and I'm grateful to everyone who sent one. For now, though, I write all the code myself. It's my full-time job, funded by sponsors, and this setup has turned out to be the most productive one by far. Once most of the design work is done, I'd like Hologram to have a core team maintaining it - but that's a later phase of the project.

Until then, the door isn't closed - it just moved. Here's the short version of why.

Writing code is the cheap part now. AI made it easy to produce, but no easier to verify, and with an external PR all of that verification lands on me, whether a human or an AI wrote the code. Given a good spec, it's faster for me to implement a feature than to properly review someone else's. That includes AI doing much of the typing - the difference is a tight feedback loop, where I iterate and benchmark along the way instead of auditing finished code after the fact.

The architecture is also moving fast. Everything that exists today is [documented on the website](https://hologram.page), and the [roadmap](https://hologram.page/docs/roadmap) shows what's coming - but not how it'll be designed. Speccing that out publicly would be wasted effort, because it could change a month later. Which is why even good external code tends to make choices that won't fit where the framework is heading. I don't bolt things on top of Hologram: every feature has to fit the whole design, and that's much easier to get right when the design discussion happens before the code exists.

Issues are where that discussion happens. You describe the problem, we talk through the options, and it turns into a spec. That costs you an hour, not a weekend. When the feature fits the roadmap, you get it implemented by the person who knows where the architecture is heading, shaped around your actual use case. **And your name goes in the release announcement.** When it doesn't fit yet, the issue still shapes priorities, and there's often a workaround in the meantime.

## What helps most

Bugs, feature requests, and docs feedback go through [GitHub issues](https://github.com/bartblast/hologram/issues). For help with your own project, the [Discord](https://discord.gg/huJWNuqt8J) and the [Elixir Forum](https://elixirforum.com/hologram) are the places to get unstuck.

If a bug or missing feature is blocking you, say so in the issue and describe what it blocks - a project, a migration, a decision whether to adopt Hologram. Blockers weigh heavily when I decide what to work on next.

- **Bug reports** with a minimal reproduction - your Hologram, Elixir, and Erlang/OTP versions, plus the smallest page or component that triggers the problem, ideally as a repo built from the [Hologram skeleton app](https://github.com/bartblast/hologram_skeleton).
- **Feature requests** that describe what you're building and where Hologram fights you, rather than a proposed implementation.
- **Docs feedback** - typos, unclear sections, missing examples. Even one-character fixes.
- **Questions** - ask on [Discord](https://discord.gg/huJWNuqt8J) or the [Elixir Forum](https://elixirforum.com/hologram), whichever you prefer. I'm on both, but Discord is busier, so answers usually come faster there. When an answer uncovers a bug or a docs gap, it graduates to an issue.
- **Ecosystem packages** - building your own package on top of Hologram is very welcome, and that code is entirely yours. Hologram aims to ship a lot of core tooling out of the box, but don't let that stop you: packages that fill a gap until official support lands are valuable even when that support is planned, and alternative approaches to what Hologram ships - extensions, integrations, different trade-offs - are always fair game. Ask on Discord or the Elixir Forum what's coming and when, so you know what you're building alongside. Just mind the [package naming conventions](https://hologram.page/reference/package-naming) - the `hologram_` prefix and `Hologram.*` namespace are reserved for official packages.
- **Spreading the word** - blog posts, talks, and example apps help more than you might think.
- **[Sponsoring the project](https://github.com/sponsors/bartblast)** - if Hologram is useful to you, sponsors are what make the full-time work possible.
