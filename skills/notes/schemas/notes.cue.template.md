```cue
date:         string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
author:       string
slug:         string & =~"^[a-z0-9-]+$"
source_notes?: [...string]
tags?:        [...string]
supersedes?:  string           // predecessor this note replaces (forward edge; authoritative)
superseded_by?: [...string]    // successor(s) that replace this note (derived reverse cache)
status?:      "current" | "superseded"
```

# <title>

<summary>

# <Background | Context | Motivation>

<content>

# <Findings | Analysis | Notes>

<content>

# <Next steps | Open questions>

<content>
