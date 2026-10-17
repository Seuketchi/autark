# Autark design

The desktop design. This folder is the only copy; the Claude canvas used to edit it has been deleted, and can be republished from these files when needed. `canvas/` holds every artboard as a `.dc.html` file, plus `canvas.json`, the layout index.

| Artboard | What it shows |
| --- | --- |
| `Main` | Desktop: top bar, Files and Terminal windows, dock |
| `Launcher` | App, file and action search |
| `AiLauncher` | Kith's launcher: Jev-picked actions and a local Ollama answer |
| `Assistant` | Chat with Kith: suggestions, actions, answers, memory approval |
| `Tasks` | Creating a scheduled task, and its result notification |
| `Persona` | Kith's name and Visor face in four states |
| `Notes` | Autark Notes: folders, note list, live preview with checklists and `[[links]]`, backlinks, graph view |
| `TaskManager` | Activity, the task manager: apps by CPU, memory, energy, disk and network, with the force-quit dialog |
| `Overview` | All windows and workspaces |
| `NotificationCenter` | Quick settings and notifications |
| `Lock` | Lock screen with fingerprint or password |
| `Settings` | Appearance, About and AI (engines, Jev features, tasks, memory, call log) |
| `FileManager` | Browsing `~/autark` in icon and list view |
| `Icons`, `AppIcon` | The app icon set, and the component that draws it |
| `Logo` | Logo directions (Loop was chosen) |
| `Colors` | Light colour systems (Linen was chosen) |
| `Wallpaper`, `TopBar`, `Dock` | Shared components used by the screens |

These are mockups for the design, not shell code. The real shell is written in Rust with GTK4 (see [the build guide](../docs/specs/build-guide.md), Step 9).
