```cue
id?: string
status?: "draft" | "proposed" | "accepted" | "deprecated" | "rejected" | "superseded"
date?: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2}:[0-9]{2}.*)?$"
author?: string
owner?: string
tags?: [...string]
references?: [...string]
supersedes?: string
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
