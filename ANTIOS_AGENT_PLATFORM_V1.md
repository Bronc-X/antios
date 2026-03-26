# ANTIOS Agent Platform V1.2

> Status: execution blueprint for `main`
> Updated: 2026-03-25
> Scope: make `antios10` a human-facing health app and an agent-facing health runtime
> Basis: current codebase, official OpenAI and Anthropic docs checked on 2026-03-25, plus public market signals from Andrej Karpathy and Anthropic product direction

---

## 1. Core Thesis

`antios10` should no longer be designed as "an app that happens to have an AI chat".

It should be designed as:

`a health state service for agents, with the iPhone app as the primary human operating surface`

That means three things at once:

1. the app is where the human sees, edits, approves, and overrides health-state decisions
2. Max is the default resident agent that reasons over the state and runs the anti-anxiety loop
3. the same state, tools, and guardrails must be callable by other agents later

The product is not the chat transcript.

The product is the continuously updated, safety-bounded, evidence-backed health state graph and the next best action derived from it.

---

## 2. Why V1.2 Needs To Be Agent-First

### 2.1 The external signal

Two market signals matter here:

- OpenAI's current developer stack has converged around tool-using agents, the Responses API, and agent runtimes instead of plain chat wrappers.
- Anthropic's current stack has converged around tool use, MCP connectivity, and computer use, which all point toward apps becoming operational surfaces and tool hosts for agents.

There is also a clear public direction signal:

- On 2026-03-22, coverage of Andrej Karpathy's "Dobby" setup described a personal agent collapsing multiple home-control apps into one agent-operated layer.
- Anthropic's computer-use direction makes the same underlying bet from the opposite side: agents will increasingly operate software surfaces, not just answer questions.

The implication for `antios10` is straightforward:

- do not build only a user app
- build a trustworthy health runtime that users see through the app
- keep the app callable and composable by other agents from day one

### 2.2 What "this app is service for agent" means in practice

It does not mean the UI disappears.

It means:

- the UI is the human approval and inspection layer
- the real product contract lives in typed state, typed tools, typed memories, typed outcomes
- every important surface in the app should correspond to a capability an agent can call

---

## 3. The Best Elegant Data Combination

This section replaces the previous vague data logic. It is the minimum elegant substrate for anti-anxiety, anti-inflammatory, anti-cancer-risk-reduction, and fitness-aware guidance using iPhone plus Apple Watch.

### 3.1 Passive data that is genuinely worth collecting

These are the highest-value passive inputs:

- HRV
- resting heart rate
- sleep duration
- sleep regularity
- sleep score or sleep efficiency proxy
- step count
- exercise minutes
- cardio fitness proxies when available
- SpO2 when available
- respiration proxies when available
- day-over-day and 7-day deltas, not only current values

### 3.2 Active data that the user should still provide

These must stay sparse and low-friction:

- anxiety level
- stress level
- body tension
- mental clarity
- energy
- dominant trigger or scenario
- whether today's action was completed
- whether the action helped, did nothing, or felt too hard

Rule:

- Home summarizes
- Max asks
- the user should never be forced to fill a full questionnaire to unlock the next useful action

### 3.3 Derived state layer

This is the real product substrate. Raw inputs must be compressed into a small decision layer:

- `arousal_load`
- `recovery_debt`
- `circadian_stability`
- `behavioral_momentum`
- `trigger_certainty`
- `action_capacity_today`
- `evidence_readiness`
- `coachability_window`

These variables, not raw tables, should drive:

- the home summary
- Bayesian uplift
- inquiry selection
- science ranking
- Max starter questions
- external agent calls

### 3.4 Memory layer

The memory ranking order should be:

1. sensor-derived memories
2. recent action outcomes
3. active plan state
4. recent self-report context
5. inquiry history
6. assistant strategy memory
7. generic knowledge

That order is the right health-specific prioritization because the system should prefer "what the body and behavior just did" over "what the assistant said three days ago."

### 3.5 Safety and privacy boundary

Externally, do not expose raw health history by default.

Expose:

- summarized state snapshot
- active plan state
- uncertainty flags
- evidence summary
- action outcome summary

Do not expose:

- full raw message history
- full raw health event history
- hidden memory store internals

---

## 4. The Correct App Interaction Workflow

The app should run one loop, not several parallel mini-products.

## 4.1 Home

Home should follow a strict three-tier loading contract:

- `T0 local`: render local snapshot and local plans immediately
- `T1 core`: refresh dashboard, recommendations, habits, profile, inquiry, active plan
- `T2 enrichment`: refresh Bayesian interpretation, proactive brief, and personalized journals

This is the right home behavior:

1. show one-sentence current state overview
2. move the actual question into `当前进度`
3. show Bayesian uplift as evidence-weighted decision support
4. show at least three personalized journal items
5. hand off execution to Max

Home must not become a second chat surface.

## 4.2 Max

Max should own:

- clarifying questions
- RAG-backed starter questions
- micro-plan generation
- evidence explanation
- plan continuation
- action review

## 4.3 Me / System Status

The five status entry points:

- `state`
- `plan`
- `signal`
- `focus`
- `max`

should be native stat surfaces, not navigation traps.

They should:

- stay in-page
- open Apple Health-style statistical sheets
- provide haptics
- optionally refresh scoped data
- never unexpectedly jump into Max

## 4.4 Science journals

This should be a true ranked evidence surface, not a decorative card.

Every item must show:

- original source link
- abstract
- match score
- explicit personalized reason
- actionable next step
- score breakdown, not just one opaque percentage

---

## 5. This App As A Service For Agents

This is the V1.2 addition that should drive the architecture.

### 5.1 Internal principle

Every major user-facing surface should map to one or more callable capabilities.

The app UI becomes:

- the inspection layer
- the approval layer
- the correction layer

The service layer becomes:

- the source of truth
- the agent interface
- the orchestration substrate

### 5.2 Core callable capabilities

V1.2 should expose these capabilities internally first:

- `observe_state_snapshot`
- `observe_signal_history`
- `observe_plan_state`
- `observe_focus_state`
- `generate_rag_questions`
- `score_bayesian_uplift`
- `retrieve_science_journals`
- `write_action_outcome`
- `refresh_signal_pipeline`
- `open_follow_up_loop`

### 5.3 The app calling external agents

The app should eventually call external agents for bounded tasks such as:

- literature expansion
- evidence reranking
- scheduling
- coaching specialization
- cross-tool workflow automation

This must happen through typed tool boundaries, not raw prompt concatenation.

### 5.4 Other agents calling the app

The app should be invokable by other agents through a narrow capability surface:

- get the latest safe state snapshot
- get current plan state
- get evidence summary
- write a suggested intervention
- write an observed outcome

The app should remain the policy-enforcing layer even when another agent calls it.

### 5.5 Future transport shape

The clean long-term transport options are:

- internal tool layer first
- MCP-compatible service boundary later
- App Intents / Siri / Shortcuts later
- optional external agent gateway later

The important design rule is:

`the capability contract must exist before the transport choice`

---

## 6. OpenAI And Anthropic Runtime Strategy

## 6.1 OpenAI

Based on current OpenAI documentation, the right OpenAI role in `antios10` is:

- agent orchestration
- typed tool calling
- evidence refresh with citations
- traceable multi-step execution
- future external-agent embedding

Recommended stack:

- `Responses API` as the primary execution surface
- tool-enabled models for web search, file search, and MCP where needed
- `Agents SDK` where traceability, handoffs, and multi-step workflows matter

OpenAI should reason over compact structured state, not a giant undifferentiated prompt.

## 6.2 Anthropic

Based on current Anthropic documentation, the right Anthropic role in `antios10` is:

- tool-rich delegated workflows
- MCP-connected execution
- computer-use or UI-operation scenarios when the workflow truly requires it
- structured external agent composition

Anthropic is especially relevant when `antios10` must participate in a larger tool graph rather than act only as a standalone app.

## 6.3 Strategic conclusion

Use the same product contract regardless of model vendor:

- typed state snapshot
- typed tools
- typed safety policy
- typed outputs

Vendor choice should change the execution engine, not the product logic.

---

## 7. Science Retrieval, Ranking, And Explanation

This section is now explicit. No more "based on scientific retrieval" placeholder copy.

### 7.1 Retrieval order

The retrieval pipeline should be:

1. curated feed API
2. curated feed queue
3. scientific search fallback

Fallback should still be personalized before display.

### 7.2 Ranking logic

The personalized match score should be computed from five explicit terms:

- `history_alignment` weight `0.34`
- `signal_alignment` weight `0.26`
- `topic_alignment` weight `0.18`
- `recency` weight `0.12`
- `authority` weight `0.10`

Formula:

`match_score = 0.34H + 0.26S + 0.18T + 0.12R + 0.10A`

Where:

- `H` measures similarity to recent user memory or recent history
- `S` measures fit to live physiological and subjective signals
- `T` measures overlap with current focus and article topic
- `R` measures publication freshness
- `A` measures source quality

### 7.3 Explanation contract

The recommendation reason must mention real causes, for example:

- recent sleep deficit
- recent elevated stress signal
- recent low-energy state
- overlap with current focus
- overlap with a retrieved recent memory
- relative source quality

It should never degrade into:

- "based on scientific retrieval"
- "based on scientific search match"
- other generic non-explanations

---

## 8. Bayesian Uplift Contract

Bayesian uplift should not feel mystical. It is a compact decision layer.

Inputs:

- prior from recent readiness, stress, and sleep state
- likelihood from body-state evidence such as HRV
- evidence weight from ranked literature

Output:

- whether the next best move is to regulate first, inquire first, or act first

The UI message should stay narrow:

- only scientific suggestions
- no grandiose claims
- no emotional fluff

---

## 9. Max Starter Questions Contract

The V1.2 rule is strict:

- starter questions must be `RAG-first`
- no mixed mode where generic templates appear before retrieved context
- template fallback is allowed only when retrieval confidence is too low

The generation chain should be:

1. aggregate user state
2. retrieve inquiry history
3. retrieve memory and knowledge context
4. generate 3 to 5 questions from retrieved context only
5. fall back only if the retrieved context is genuinely insufficient

This keeps the first user-facing question honest.

---

## 10. Immediate Codebase Implications

V1.2 means the codebase should converge toward these modules:

- `state snapshot builder`
- `signal pipeline`
- `science personalization engine`
- `bayesian policy engine`
- `rag question generator`
- `agent capability registry`
- `human approval surfaces`

Concrete immediate moves:

1. keep Home on the three-tier load contract
2. keep Me on local stat sheets, not navigation
3. keep science ranking explicit and inspectable
4. keep Max starter questions on the same RAG substrate as the rest of Max
5. keep all future agent entry points behind typed capabilities

---

## 11. Final Direction

The winning version of `antios10` is not:

- a prettier health dashboard
- a nicer chatbot
- a loose pile of anti-anxiety features

The winning version is:

`a trustworthy personal health state service that humans operate through the app and agents can safely compose around`

That is the V1.2 north star.
