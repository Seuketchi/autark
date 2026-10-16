# Autark AI layer

Autark has two AI engines behind one daemon. Jev makes fast typed decisions in the cloud. Ollama generates text locally, so nothing leaves the laptop. Code always does the actual work; AI only decides or explains. Settled on 2026-10-16.

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
| Conversation | The launcher continues into a chat panel. Each turn is routed (action, question or search), and Ollama answers with the earlier turns as context. History is kept in `~/.local/share/autark-ai/conversations/` | Kept 7 days, configurable |
| Memory | Facts about you ("builds Autark in the evenings", "project lives in ~/autark"). The assistant proposes each one and you approve it; nothing is saved silently. Stored as plain TOML in `~/.config/autark-ai/memory.toml`, and viewable and editable in Settings › AI › Memory | On, approval required |
| Suggestions | Code detects events (battery low, build finished, new Wi-Fi network). Jev scores whether each is worth interrupting you, given Focus and your memory. Suggestions appear as cards and never act on their own | At most 3 an hour; each has "don't suggest again" |

Memory goes to Jev only as the specific fields a decision needs, and only for features where Jev is turned on.

## Tasks

Tasks are scheduled prompts, like Grok Tasks, but they run on the laptop instead of in a cloud. Example: "every morning at 8, summarise last night's build log".

| Part | How it works |
| --- | --- |
| Creating | Tell the assistant, or add one in Settings › AI › Tasks. The sentence is turned into a task: name, schedule, prompt, the inputs it may read (files, URLs), and how to deliver it. You confirm before it's saved |
| Scheduling | Code owns the schedule, not the AI. Each task is a systemd user timer (`autark-task@<id>.timer`) with `Persistent=true`, so runs missed while the laptop was asleep catch up |
| Running | `autark-ai` fetches the inputs with code, then runs the prompt with Ollama locally. Each run is a sandboxed service that can only write its own result, and it's time-limited |
| Delivery | A notification-centre card with action buttons. It shows as a banner only if it's rated urgent and Focus allows it, and the lock screen hides the content. The result is also saved in `~/.local/share/autark-ai/tasks/<id>/` |
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

## Build

- **Step 8:** build Ollama from source and pull one small model.
- **Step 9:** add `autark-ai` to the shell's Cargo workspace, next to the bar, dock and launcher.

## Open

- [ ] TypeSafe API key and pricing ([Models](https://docs.typesafe.ai/models)).
- [ ] Which Ollama model. Measure tokens per second on this laptop (i5-1135G7, 30 GB RAM) before choosing.
