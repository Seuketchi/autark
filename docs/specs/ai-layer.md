# Autark AI layer

Autark has two AI engines behind one daemon. Jev makes fast typed decisions in the cloud. Ollama generates text on hardware you own. The assistant, Kith, runs on your own server so your phone and laptop share it. Code always does the actual work; AI only decides or explains. Settled on 2026-10-16.

## The two engines

| | Jev (TypeSafe) | Ollama |
| --- | --- | --- |
| Runs | Cloud API: `POST https://api.typesafe.ai/v1/systemone` | On this laptop: `http://localhost:11434` |
| Returns | Typed decisions: Choice (one of a set), Noul (yes/no probability), Score (degree) | Generated text, or JSON that matches a schema |
| Speed | About 150 ms per decision ([TypeSafe's figure](https://docs.typesafe.ai/concepts/use-case-map)) | Seconds. Small models run on the CPU, since there's no discrete GPU |
| Privacy | Sends the text it judges to TypeSafe | Nothing leaves the machine |
| Input | Text only ([System One](https://docs.typesafe.ai/concepts/system-one)) | Text |
| Used for | Routing commands, notification urgency, command safety, file ranking | Explanations, summaries, drafting, and the offline fallback for routing |

## Where it shows up

| Place | What happens | Engine |
| --- | --- | --- |
| Launcher | "dim the screen and mute" is turned into actions with arguments (brightness 30%, volume muted), which code then runs | Jev (Choice per action, plus argument fill) |
| Launcher | "why did my last build fail?" gets an answer from the build log | Jev routes it, Ollama answers |
| Notification centre | Each notification gets an urgency score; Focus mode lets only urgent ones through | Jev (Score) |
| Terminal | A command that looks destructive or irreversible, typed by you or an AI agent, asks for confirmation before it runs | Jev (Noul) |
| File manager | Search by meaning: candidates found by code, ranked by relevance | Jev (Score per candidate) |
| Settings search | "my screen is too bright at night" opens Night light | Jev (Choice) |

## Assistant

The launcher grows into a personal assistant called **Kith**, like Grok, but split the Autark way. Its face is the Visor: dark glass with glowing sage eyes, drawn as vectors and animated for idle, listening, thinking and speaking. Jev decides, code acts, Ollama writes, and everything it remembers stays on the encrypted disk.

| Capability | How it works | Default |
| --- | --- | --- |
| Conversation | The launcher continues into a chat panel. Each turn is routed (action, question or search), and Kith answers with the earlier turns as context. History lives with Kith's brain, so a chat started on the phone continues on the laptop | Kept 7 days, configurable |
| Memory | Facts about you ("builds Autark in the evenings", "project lives in ~/autark"). The assistant proposes each one and you approve it; nothing is saved silently. Stored with Kith's brain (Hermes memory on your box), with a read-only copy on the laptop for standalone mode. Viewable and editable in Settings › AI › Memory | On, approval required |
| Suggestions | Code detects events (battery low, build finished, new Wi-Fi network, an app using high CPU or draining the battery for minutes, read from `autark-stats`). Jev scores whether each is worth interrupting you, given Focus and your memory. Suggestions appear as cards and never act on their own | At most 3 an hour; each has "don't suggest again" |

Memory goes to Jev only as the specific fields a decision needs, and only for features where Jev is turned on.

## One Kith on every device

Kith's brain is a Hermes agent (Nous Research's open-source agent, the same base as Wren) on a box where only you have root. Your phone reaches it over Signal. Your laptop reaches it through `autark-ai` over Tailscale. Kith replaces Wren: one memory, one personality, and Wren's scheduled jobs become Kith tasks.

Everything is configurable, so someone else running Autark can point Kith at their own setup.

| Part | Default | Configurable to |
| --- | --- | --- |
| Brain | **For now:** standalone Hermes on the laptop, with no phone access while it sleeps. **Later:** Hermes on your own box, reached over Tailscale | Any Hermes host you run |
| Model | Ollama wherever the brain runs (the laptop for now). A box needs about 16 GB of RAM for a 7–8B model | Any Ollama or OpenAI-compatible endpoint |
| Phone | Signal (end-to-end encrypted) | Telegram, Matrix or WhatsApp, which Hermes also supports |
| Laptop | `autark-ai` talks to Hermes directly over Tailscale, with no chat app | |
| Web | Firecrawl, self-hosted on your network, through `firecrawl-mcp` | Off, or another Firecrawl instance |
| Fast decisions | Jev, opt-in per feature | Off |
| Persona | Kith, defined in Hermes' `SOUL.md` | Your own name and voice |

**Acting on the laptop.** `autark-ai` runs an MCP server, reachable only over Tailscale, that offers laptop actions to Kith. Each action has a tier, as in Wren: auto, ask or never. Anything the phone asks for that changes state needs a confirmation on the laptop, and destructive actions are never allowed remotely.

**When the box is unreachable,** the laptop drops to standalone mode: local Ollama and the read-only memory copy. New memories wait until it reconnects.

**Moving from Wren** happens once Kith has its own box. Until then Wren keeps running unchanged on `tristan-hermes`, which isn't suitable for Kith: the host's owner has root on it, and it has only 3 GB of RAM.


1. Rewrite Wren's persona as Kith's `SOUL.md`.
2. Move Wren's jobs over as Kith tasks: morning report 07:30, learning digest 18:30, evening check 21:30, weekly review Sunday 20:00.
3. Move the memory files and Wren's domain database.
4. Switch the model from DeepSeek to the self-hosted Ollama, and the channel from Telegram to Signal.
5. Retire Wren's gateway. Telegram allows only one poller anyway.

## Work tasks: Kith to Claude Code

Kith dispatches company work but never does it. Your Claude account is company-owned (the reason Wren runs on Hermes), so company code goes to Claude Code and personal work stays with Kith. Hermes ships a `claude-code` skill for exactly this handoff.

1. **Recognise.** You tell Kith something like "build this feature in the mobile app". Kith classifies it as work for a known repo, using a project map in config (for example `the-mobile-app` → `~/projects/the-mobile-app`).
2. **Confirm.** Kith asks before starting: "Start Claude Code in `~/projects/the-mobile-app` with: …?" Starting a work task is always an *ask* action.
3. **Run on the laptop.** Kith calls the laptop's MCP tool `start_coding_task(repo, prompt)`. Claude Code runs there, with the company login, in a terminal you can watch and step into. Small, read-only jobs can use headless mode (`claude -p`). This holds even after Kith moves to its own box: company code and credentials never leave the laptop.
4. **Keep the boundary.** Only your request text goes to Claude Code. Kith gets back a short status (running, needs your input, PR ready, failed) and a link, never the code or the transcript. Claude Code never sees Kith's memory.
5. **Report back.** A Claude Code hook tells `autark-ai` when the session stops or needs you. Kith then notifies you on the laptop, and over Signal once it has its own box.

Claude Code's own commands still pass the terminal safety check: a hook that runs before each command asks `autark-ai` `Check(command)`, so destructive commands get confirmed and logged like yours. Claude Code's file access is governed by its own permission settings, and Autark can sandbox it to project folders. Anything it reads, including notes, goes to Anthropic.

## Tasks

Tasks are scheduled prompts, like Grok Tasks, but they run on hardware you own instead of in a cloud. Example: "every morning at 8, summarise last night's build log".

| Part | How it works |
| --- | --- |
| Creating | Tell the assistant, or add one in Settings › AI › Tasks. The sentence is turned into a task: name, schedule, prompt, the inputs it may read (files, URLs), and how to deliver it. You confirm before it's saved |
| Scheduling | Code owns the schedule, not the AI. By default tasks run as Hermes cron jobs on Kith's box, so they fire even while the laptop is asleep. In standalone mode each task is a systemd user timer (`autark-task@<id>.timer`) with `Persistent=true`, so missed runs catch up |
| Running | Inputs are fetched with code; laptop files come through the laptop's MCP tools. The prompt runs on Ollama. Each run is sandboxed, can only write its own result, and is time-limited |
| Delivery | A Signal message on the phone and a notification-centre card with action buttons on the laptop. It shows as a banner only if it's rated urgent and Focus allows it, and the lock screen hides the content. The result is also saved in `~/.local/share/autark-ai/tasks/<id>/` |
| Limits | 20 tasks and 5 minutes per run by default, both configurable |

Useful starting tasks are a morning build summary, a weekly check of [BLFS security advisories](https://www.linuxfromscratch.org/blfs/advisories/) against installed packages, and a monthly battery health report.

## Daemon: `autark-ai`

A Rust service on the session D-Bus, `org.autark.AI1`. Every shell piece talks to it instead of to the engines directly.

- `Route(text)` returns typed actions, a question, or a search.
- `Rank(query, items)` returns relevance scores.
- `Check(command)` returns a risk probability.
- `Ask(prompt, context)` streams a generated answer.
- `Chat(session, text)` streams one assistant turn, including any actions it proposes.
- `ProposeMemory(fact)` asks you to approve a memory; `Forget(id)` removes one.
- `Suggestion` is a signal the notification centre and assistant panel listen for.
- `CreateTask(spec)`, `ListTasks()` and `RunTask(id)` manage tasks; `TaskFinished` is a signal carrying the result.
- `StartCodingTask(repo, prompt)` starts a Claude Code session after you confirm; `CodingTaskStatus` is a signal (running, needs input, PR ready, failed).

## Rules

- **Code acts, AI decides.** Actions run through D-Bus and systemd, never as text generated by a model.
- **Low confidence means show, don't act.** If Jev isn't confident, the launcher lists the options instead of running one.
- **Destructive actions always confirm,** whatever the AI says.
- **Local-only mode** sends everything to Ollama, using JSON-schema output for routing. It turns on automatically when offline.
- **Opt-in.** AI is off until you turn it on in Settings, which also has a switch per feature.
- **Every AI call is logged locally** (`~/.local/state/autark-ai/log`) with its input, answer and confidence, so mistakes can be traced.
- **Thresholds are tuned on your own usage,** not copied from examples.

## Settings › AI

- Jev on or off. The API key is stored in the Secret Service keyring.
- Ollama model selection.
- A local-only mode switch.
- A switch for each feature in the table above.
- A link to the call log.
- Kith's brain: a server address, or standalone on this laptop.
- The phone channel and the Firecrawl address.

## Build

- **Step 8:** build Ollama from source and pull one small model.
- **Step 9:** add `autark-ai` to the shell's Cargo workspace, next to the bar, dock and launcher.

## Open

- [ ] A box for Kith with about 16 GB of RAM, where only you have root.
- [ ] Migrate Wren to Kith (steps above).

- [ ] TypeSafe API key and pricing ([Models](https://docs.typesafe.ai/models)).
- [ ] Which Ollama model. Measure tokens per second on the target laptop before choosing.
