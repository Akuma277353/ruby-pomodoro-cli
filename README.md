# Ruby Pomodoro CLI

A lightweight **Pomodoro + Focus Tracker** written in pure Ruby (**no gems**).  
Windows-friendly: the timer runs in the background so your terminal isn’t blocked.

## Features

- Start a Pomodoro timer from the terminal
- Background timer (does not block the terminal)
- Auto-saves the session when time is up
- Stop early (saves) or cancel (does not save)
- Daily focus summary (`today`)
- Last 7 days totals (`stats`)
- Stores sessions locally in JSON (ignored by `.gitignore`)

## Requirements

- Ruby installed
- No external gems required

Check Ruby:

```bash
ruby -v
```

## Setup  

Clone the  repo and run commands from the prohect folder:
```bash
git clone <your-repo-url>
cd <your-repo-folder>
```

## Usage  
Start a 25-minute session:
```bash
ruby pomo.rb start 25 "Session-Name"
```

Check how much time is left:
```bash
ruby pomo.rb status
```

Stop early and save:
```bash
ruby pomo.rb stop
```

Cancel without saving:
```bash
ruby pomo.rb cancel
```

Show today's focus minutes + session:
```bash
ruby pomo.rb today
```

Show totals for the last 7 days:
```bash
ruby pomo.rb stats
```

## Data Files
The app stores local data in:  
- `pomo-sessions.json` (all saved sessions)
- `pomo_active.json` (currently running session)

## Example Workflow
```bash
ruby pomo.rb start 25 "Study"
# focus ..
ruby pomo.rb status
ruby pomo.rb today
```
