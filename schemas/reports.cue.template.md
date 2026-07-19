```cue
id?: string
status?: "draft" | "proposed" | "accepted" | "deprecated" | "rejected" | "superseded"
date?: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2}:[0-9]{2}.*)?$"
intent?: "normative" | "descriptive"
author?: string
owner?: string
tags?: [...string]
references?: [...string]
supersedes?: string            // predecessor this report replaces (forward edge; authoritative)
superseded_by?: [...string]    // successor(s) that replace this report (derived reverse cache)
```

# <title>

<summary (short)>

# <Observation | Motivation | Background | Context | Problem>

<content>

# <Orientation | Reasoning | Analysis | Discussion>

<content>

# <Decision | Next steps | Plan | Implementation Strategy>

<content>

# <Action | Results | Consequences | Ramifications>

<content (list)>
