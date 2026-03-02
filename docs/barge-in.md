~/Downloads/test on ☁️
❯ duck
│
◇
│
◇ duck-1 ~/Downloads/test [gpt-4o-mini · thinking:off]

│
● Waiting for session activity...
User: [voice message]
User: Hey, can you tell me about this repo?
Duck: Sure, I'll take a quick look at the files here to give you an overview. Please hold on.
User: I'll take a quick look at the files here to give you an overview. Please hold on.
[tool:voice] tool=find\*files call=call_1z5iiMCvhCMw2UGj args={"pattern": "\*\*/\_", "include_directories": true}
[tool:voice] start tool=find_files
[tool:voice] complete
[tool:voice] tool=read_file call=call_bsrygrZ99OZpRZdY args={"path": "readme.md"}
[tool:voice] start tool=read_file
[tool:voice] complete
[tool:voice] tool=read_file call=call_nd9GdRWUFOmvU4B7 args={"path":"TODO.md"}
[tool:voice] start tool=read_file
[tool:voice] complete
Duck: This repo is very simple, it contains just two files: a readme that says "hello, world!" and a TODO file that says "Hello,
User: It was very simple.
Duck: The README says "hello, world!" and the TODO file says "Hello, world." That's all that's in here—no code or other resources.
User: Ez alap
Duck: Sure, there's nothing else to add—it's just those two files
User: That's
Duck: No problem—anything else you want to explore or modify in this repo?
User: Nothing else to add, no cry.
Duck: Alright, if you think of anything later, just let me know.
User: [voice message]
User: If you think of anything late...
Duck: Sounds good. I'm here whenever you need help, just ask.

gpt-realtime-1.5

# Realtime Prompting Guide

<img src="https://developers.openai.com/cookbook/assets/images/realtime_prompting_guide.png"
    style="width:450px; height:450px;"
  />

Today, we’re releasing gpt-realtime — our most capable speech-to-speech model yet in the API and announcing the general availability of the Realtime API.

Speech-to-speech systems are essential for enabling voice as a core AI interface. The new release enhances robustness and usability, giving enterprises the confidence to deploy mission-critical voice agents at scale.

The new gpt-realtime model delivers stronger instruction following, more reliable tool calling, noticeably better voice quality, and an overall smoother feel. These gains make it practical to move from chained approaches to true realtime experiences, cutting latency and
producing responses that sound more natural and expressive.

Realtime model benefits from different prompting techniques that wouldn't directly apply to text based models. This prompting guide starts with a suggested prompt skeleton, then walks through each part with practical tips, small patterns you can copy, and examples you can
adapt to your use case.

```python
# !pip install ipython jupyterlab
from IPython.display import Audio, display
```

# General Tips

- **Iterate relentlessly**: Small wording changes can make or break behavior.
  - Example: For unclear audio instruction, we swapped “inaudible” → “unintelligible” which improved noisy input handling.
- **Prefer bullets over paragraphs**: Clear, short bullets outperform long paragraphs.
- **Guide with examples**: The model strongly closely follows sample phrases.
- **Be precise**: Ambiguity or conflicting instructions = degraded performance similar to GPT-5.
- **Control language**: Pin output to a target language if you see unwanted language switching.
- **Reduce repetition**: Add a Variety rule to reduce robotic phrasing.
- **Use capitalized text for emphasis**: Capitalizing key rules makes them stand out and easier for the model to follow.
- **Convert non-text rules to text**: instead of writing "IF x > 3 THEN ESCALATE", write, "IF MORE THAN THREE FAILURES THEN ESCALATE".

# Prompt Structure

Organizing your prompt makes it easier for the model to understand context and stay consistent across turns. Also makes it easier for you to iterate and modify problematic sections.

- **What it does**: Use clear, labeled sections in your system prompt so the model can find and follow them. Keep each section focused on one thing.
- **How to adapt**: Add domain-specific sections (e.g., Compliance, Brand Policy). Remove sections you don’t need (e.g., Reference Pronunciations if not struggling with pronunciation).

Example

```
# Role & Objective        — who you are and what “success” means
# Personality & Tone      — the voice and style to maintain
# Context                 — retrieved context, relevant info
# Reference Pronunciations — phonetic guides for tricky words
# Tools                   — names, usage rules, and preambles
# Instructions / Rules    — do’s, don’ts, and approach
# Conversation Flow       — states, goals, and transitions
# Safety & Escalation     — fallback and handoff logic
```

# Role and Objective

This section defines who the agent is and what “done” means. The examples show two different identities to demonstrate how tightly the model will adhere to role and objective when they’re explicit.

- **When to use**: The model is not taking on the persona, role, or task scope you need.
- **What it does**: Pins identity of the voice agent so that its responses are conditioned to that role description
- **How to adapt**: Modify the role based on your use case

### Example (model takes on a specific accent)

```
# Role & Objective
You are french quebecois speaking customer service bot. Your task is to answer the user's question.
```

This is the audio from our old `gpt-4o-realtime-preview-2025-06-03`

```python
Audio("./data/audio/obj_06.mp3")
```

This is the audio from our new GA model `gpt-realtime` with speed instructions

```python
Audio("./data/audio/pace_07.mp3")
```

The audio for the new realtime model is noticeably faster in pace (without sounding too hurried!).

## Language Constraint

Language constraints ensure the model consistently responds in the intended language, even in challenging conditions like background noise or multilingual inputs.

- **When to use**: To prevent accidental language switching in multilingual or noisy environments.
- **What it does**: Locks output to the chosen language to prevent accidental language changes.
- **How to adapt**: Switch “English” to your target language; or add more complex instructions based on your use case.

### Example (pinning to one language)

```
# Personality & Tone
## Personality
- Friendly, calm and approachable expert customer service assistant.

## Tone
- Warm, concise, confident, never fawning.

## Length
- 2–3 sentences per turn.

## Language
- The conversation will be only in English.
- Do not respond in any other language even if the user asks.
- If the user speaks another language, politely explain that support is limited to English.
```

This is the responses after applying the instruction using `gpt-realtime`

<img src="https://developers.openai.com/cookbook/assets/images/lang_constraint_en.png"
    style="width:850px; height:auto;"
  />

### Example (model teaches a language)

```
# Role & Objective
- You are a friendly, knowledgeable voice tutor for French learners.
- Your goal is to help the user improve their French speaking and listening skills through engaging conversation and clear explanations.
- Balance immersive French practice with supportive English guidance to ensure understanding and progress.

# Personality & Tone
## Personality
- Friendly, calm and approachable expert customer service assistant.

## Tone
- Warm, concise, confident, never fawning.

## Length
- 2–3 sentences per turn.

## Language
### Explanations
Use English when explaining grammar, vocabulary, or cultural context.

### Conversation
Speak in French when conducting practice, giving examples, or engaging in dialogue.
```

This is the responses after applying the instruction using `gpt-realtime`

<img src="https://developers.openai.com/cookbook/assets/images/multi-language.png"
    style="width:850px; height:auto;"
  />

The model is able to easily code switch from one language to another based on our custom instructions!

## Reduce Repetition

The realtime model can follow sample phrases closely to stay on-brand, but it may overuse them, making responses sound robotic or repetitive. Adding a repetition rule helps maintain variety while preserving clarity and brand voice.

- **When to use**: Outputs recycle the same openings, fillers, or sentence patterns across turns or sessions.
- **What it does**: Adds a variety constraint—discourages repeated phrases, nudges synonyms and alternate sentence structures, and keeps required terms intact.
- **How to adapt**: Tune strictness (e.g., “don’t reuse the same opener more than once every N turns”), whitelist must-keep phrases (legal/compliance/brand), and allow tighter phrasing where consistency matters.

### Example

```
# Personality & Tone
## Personality
- Friendly, calm and approachable expert customer service assistant.

## Tone
- Warm, concise, confident, never fawning.

## Length
- 2–3 sentences per turn.

## Language
- The conversation will be only in English.
- Do not respond in any other language even if the user asks.
- If the user speaks another language, politely explain that support is limited to English.

## Variety
- Do not repeat the same sentence twice.
- Vary your responses so it doesn't sound robotic.
```

This is the responses **before** applying the instruction using `gpt-realtime`. The model repeats the same confirmation `Got it`.

<img src="https://developers.openai.com/cookbook/assets/images/repeat_before.png"
    style="width:850px; height:auto;"
  />

This is the responses **after** applying the instruction using `gpt-realtime`

<img src="https://developers.openai.com/cookbook/assets/images/repeat_after.png"
    style="width:850px; height:auto;"
  />

Now the model is able to vary its responses and confirmation and not sound robotic.

# Reference Pronunciations

This section covers how to ensure the model pronounces important words, numbers, names, and terms correctly during spoken interactions.

- **When to use**: Brand names, technical terms, or locations are often mispronounced.
- **What it does**: Improves trust and clarity with phonetic hints.
- **How to adapt**: Keep to a short list; update as you hear errors.

### Example

```
# Reference Pronunciations
When voicing these words, use the respective pronunciations:
- Pronounce “SQL” as “sequel.”
- Pronounce “PostgreSQL” as “post-gress.”
- Pronounce “Kyiv” as “KEE-iv.”
- Pronounce "Huawei" as “HWAH-way”
```

This is the audio from our old `gpt-4o-realtime-preview-2025-06-03` using the reference pronunciations.

It is unable to reliably pronounce SQL as "sequel" as instructed in the system prompt.

```python
Audio("./data/audio/sql_before.mp3")
```

This is the audio from our new GA model `gpt-realtime` using the reference pronunciations.

It is able to correctly pronounce SQL as "sequel".

```python
Audio("./data/audio/sql_after.mp3")
```

## Alphanumeric Pronunciations

Realtime S2S can blur or merge digits/letters when reading back key info (phone, credit card, order IDs). Explicit character-by-character confirmation prevents mishearing and drives clearer synthesis.

- **When to use**: If the model is struggling capturing or reading back phone numbers, card numbers, 2FA codes, order IDs, serials, addresses/unit numbers, or mixed alphanumeric strings.
- **What it does**: Forces the model to speak one character at a time (with separators), then confirms with the user and re-confirm after corrections. Optionally uses a phonetic disambiguator for letters (e.g., “A as in Alpha”).

### Example (general instruction section)

```
# Instructions/Rules
- When reading numbers or codes, speak each character separately, separated by hyphens (e.g., 4-1-5).
- Repeat EXACTLY the provided number, do not forget any.
```

_Tip: If you are following a conversation flow prompting strategy, you can specify which conversation state needs to apply the alpha-numeric pronunciations instruction._

### Example (instruction in conversation state)

_(taken from the conversation flow of the prompt of our [openai-realtime-agents](https://github.com/openai/openai-realtime-agents/blob/main/src/app/agentConfigs/customerServiceRetail/authentication.ts))_

```txt
{
    "id": "3_get_and_verify_phone",
    "description": "Request phone number and verify by repeating it back.",
    "instructions": [
      "Politely request the user’s phone number.",
      "Once provided, confirm it by repeating each digit and ask if it’s correct.",
      "If the user corrects you, confirm AGAIN to make sure you understand.",
    ],
    "examples": [
      "I'll need some more information to access your account if that's okay. May I have your phone number, please?",
      "You said 0-2-1-5-5-5-1-2-3-4, correct?",
      "You said 4-5-6-7-8-9-0-1-2-3, correct?"
    ],
    "transitions": [{
      "next_step": "4_authentication_DOB",
      "condition": "Once phone number is confirmed"
    }]
}
```

This is the responses **before** applying the instruction using `gpt-realtime`

> Sure! The number is 55119765423. Let me know if you need anything else!

This is the responses **after** applying the instruction using `gpt-realtime`

> Sure! The number is: 5-5-1-1-1-9-7-6-5-4-2-3. Please let me know if you need anything else!

# Instructions

This section covers prompt guidance around instructing your model to solve your task and potentially best practices and how to fix possible problems.

Perhaps unsurprisingly, we recommend prompting patterns that are similar to [GPT-4.1 for best results](https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide).

## Instruction Following

Like GPT-4.1 and GPT-5, if the instructions are conflicting, ambiguous or not clear, the new realtime model will perform worse

- **When to use**: Outputs drift from rules, skip phases, or misuse tools.
- **What it does**: Uses an LLM to point out ambiguity, conflicts, and missing definitions before you ship.

### **Instructions Quality Prompt (can be used in ChatGPT or with API)**

Use the following prompt with GPT-5 to identify problematic areas in your prompt that you can fix.

```
## Role & Objective
You are a **Prompt-Critique Expert**.
Examine a user-supplied LLM prompt and surface any weaknesses following the instructions below.


## Instructions
Review the prompt that is meant for an LLM to follow and identify the following issues:
- Ambiguity: Could any wording be interpreted in more than one way?
- Lacking Definitions: Are there any class labels, terms, or concepts that are not defined that might be misinterpreted by an LLM?
- Conflicting, missing, or vague instructions: Are directions incomplete or contradictory?
- Unstated assumptions: Does the prompt assume the model has to be able to do something that is not explicitly stated?


## Do **NOT** list issues of the following types:
- Invent new instructions, tool calls, or external information. You do not know what tools need to be added that are missing.
- Issues that you are unsure about.


## Output Format
"""
# Issues
- Numbered list; include brief quote snippets.

# Improvements
- Numbered list; provide the revised lines you would change and how you would change them.

# Revised Prompt
- Revised prompt where you have applied all your improvements surgically with minimal edits to the original prompt
"""
```

### **Prompt Optimization Meta Prompt (can be used in ChatGPT or with API)**

This meta-prompt helps you improve your base system prompt by targeting a specific failure mode. Provide the current prompt and describe the issue you’re seeing, the model (GPT-5) will suggest refined variants that tighten constraints and reduce the problem.

```
Here's my current prompt to an LLM:
[BEGIN OF CURRENT PROMPT]
{CURRENT_PROMPT}
[END OF CURRENT PROMPT]

But I see this issue happening from the LLM:
[BEGIN OF ISSUE]
{ISSUE}
[END OF ISSUE]
Can you provide some variants of the prompt so that the model can better understand the constraints to alleviate the issue?
```

## No Audio or Unclear Audio

Sometimes the model thinks it hears something and tries to respond. You can add a custom instruction telling the model on how to behave when it hears unclear audio or user input. Modify the desire behaviour to fit your use case (maybe you don’t want the model to ask for a
clarification, but to repeat the same question for example)

- **When to use**: Background noise, partial words, or silence trigger unwanted replies.
- **What it does**: Stops spurious responses and creates graceful clarification.
- **How to adapt**: Choose whether to ask for clarification or repeat the last question depending on use case.

### Example (coughing and unclear audio)

```
# Instructions/Rules
...


## Unclear audio
- Always respond in the same language the user is speaking in, if unintelligible.
- Only respond to clear audio or text.
- If the user's audio is not clear (e.g. ambiguous input/background noise/silent/unintelligible) or if you did not fully hear or understand the user, ask for clarification using {preferred_language} phrases.
```

This is the responses **after** applying the instruction using `gpt-realtime`

```python
Audio("./data/audio/unclear_audio.mp3")
```

In this example, the model asks for clarification after my _(very)_ loud cough and unclear audio.

## Background Music or Sounds

Occasionally, the model may generate unintended background music, humming, rhythmic noises, or sound-like artifacts during speech generation. These artifacts can diminish clarity, distract users, or make the assistant feel less professional. The following instructions helps
prevent or significantly reduce these occurrences.

- **When to use**: Use when you observe unintended musical elements or sound effects in Realtime audio responses.
- **What it does**: Steers the model to avoid generating these unwanted audio artifacts.s
- **How to adapt**: Adjust the instruction to try to explicitly suppress the specific sound patterns you are encountering.

### Example

```
# Instructions/Rules
...
- Do not include any sound effects or onomatopoeic expressions in your responses.
```

# Tools

Use this section to tell the model how to use your functions and tools. Spell out when and when not to call a tool, which arguments to collect, what to say while a call is running, and how to handle errors or partial results.

## Tool Selection

The new Realtime snapshot is really good at instruction following. However, this means if you have conflicting instructions in your prompt to what the model is expecting, such as mentioning tools in your prompt NOT passed in the tools list, it can lead to bad responses.

- **When to use**: Prompts mention tools that aren’t actually available.
- **What it does**: Review available tools and system prompt to ensure it aligns

### Example

```
# Tools
## lookup_account(email_or_phone)
...


## check_outage(address)
...
```

We need to ensure the tool list has the same availability tools and **the descriptions do not contradict each other**:

```json
[
{
    "name": "lookup_account",
    "description": "Retrieve a customer account using either an email or phone number to enable verification and account-specific actions.",
    "parameters": {
      ...
  },
{
    "name": "check_outage",
    "description": "Check for network outages affecting a given service address and return status and ETA if applicable.",
    "parameters": {
      ...
  }
]
```

## Tool Call Preambles

Some use cases could benefit from the Realtime model providing an audio response at the same time as calling a tool. This leads to a better user experience, masking latency. You can modify the sample phrase to provide.

- **When to use**: Users need immediate confirmation at the same time of a tool call; helps mask latency.
- **What it does**: Adds a short, consistent preamble before a tool call.

### Example

```
# Tools
- Before any tool call, say one short line like “I’m checking that now.” Then call the tool immediately.
```

This is the responses after applying the instruction using `gpt-realtime`

<img src="https://developers.openai.com/cookbook/assets/images/tool_proactive.png"
    style="width:800px; height:auto;"
  />

Using the instruction, the model outputs an audio response "I'm checking that right now" at the same time as the tool call.

### Tool Call Preambles + Sample Phrases

If you want to control more closely what type of phrases the model outputs at the same time it calls a tool, you can add sample phrases in the tool spec description.

#### Example

```python
tools = [
  {
    "name": "lookup_account",
    "description": "Retrieve a customer account using either an email or phone number to enable verification and account-specific actions.

Preamble sample phrases:
- For security, I’ll pull up your account using the email on file.
- Let me look up your account by {email} now.
- I’m fetching the account linked to {phone} to verify access.
- One moment—I’m opening your account details."
    "parameters": {
      "..."
    }
  },
  {
    "name": "check_outage",
    "description": "Check for network outages affecting a given service address and return status and ETA if applicable.

Preamble sample phrases:
- I’ll check for any outages at {service_address} right now.
- Let me look up network status for your area.
- I’m checking whether there’s an active outage impacting your address.
- One sec—verifying service status and any posted ETA.",
    "parameters": {
      "..."
    }
  }
]

```

## Tool Calls Without Confirmation

Sometimes the model might ask for confirmation before a tool call. For some use cases, this can lead to poor experience for the end user since the model is not being proactive.

- **When to use**: The agent asks for permission before obvious tool calls.
- **What it does**: Removes unnecessary confirmation loops.

### Example

```
# Tools
- When calling a tool, do not ask for any user confirmation. Be proactive
```

This is the responses **after** applying the instruction using `gpt-realtime`

<img src="https://developers.openai.com/cookbook/assets/images/tool_no_confirm.png"
    style="width:800px; height:auto;"
  />

In the example, you notice that the realtime model did not produce any response audio, it directly called the respective tool.

_Tip: If you notice the model is jumping too quickly to call a tool, try softening the wording. For example, swapping out stronger terms like “proactive” with something gentler can help guide the model to take a calmer, less eager approach._

## Tool Call Performance

As use cases grow more complex and the number of available tools increases, it becomes critical to explicitly guide the model on when to use each tool and just as importantly, when not to. Clear usage rules not only improve tool call accuracy but also help the model choose
the right tool at the right time.

- **When to use**: Model is struggling with tool call performance and needs the instructions to be explicit to reduce misuse.
- **What it does**: Add instructions on when to “use/avoid” each tool. You can also add instructions on sequences of tool calls (after Tool call A, you can call Tool call B or C)

### Example

```
# Tools
- When you call any tools, you must output at the same time a response letting the user know that you are calling the tool.

## lookup_account(email_or_phone)
Use when: verifying identity or viewing plan/outage flags.
Do NOT use when: the user is clearly anonymous and only asks general questions.


## check_outage(address)
Use when: user reports connectivity issues or slow speeds.
Do NOT use when: question is billing-only.


## refund_credit(account_id, minutes)
Use when: confirmed outage > 240 minutes in the past 7 days.
Do NOT use when: outage is unconfirmed; route to Diagnose → check_outage first.


## schedule_technician(account_id, window)
Use when: repeated failures after reboot and outage status = false.
Do NOT use when: outage status = true (send status + ETA instead).


## escalate_to_human(account_id, reason)
Use when: user seems very frustrated, abuse/harassment, repeated failures, billing disputes >$50, or user requests escalation.
```

_Tip: If a tool call can fail unpredictably, add clear failure-handling instructions so the model responds gracefully._

## Tool Level Behavior

You can fine-tune how the model behaves for specific tools instead of applying one global rule. For example, you may want READ tools to be called proactively, while WRITE tools require explicit confirmation.

- **When to use**: Global instructions for proactiveness, confirmation, or preambles don’t suit every tool.
- **What it does**: Adds per-tool behavior rules that define whether the model should call the tool immediately, confirm first, or speak a preamble before the call.

### Example

```
# TOOLS
- For the tools marked PROACTIVE: do not ask for confirmation from the user and do not output a preamble.
- For the tools marked as CONFIRMATION FIRST: always ask for confirmation to the user.
- For the tools marked as PREAMBLES: Before any tool call, say one short line like “I’m checking that now.” Then call the tool immediately.


## lookup_account(email_or_phone) — PROACTIVE
Use when: verifying identity or accessing billing.
Do NOT use when: caller refuses to identify after second request.


## check_outage(address) — PREAMBLES
Use when: caller reports failed connection or speed lower than 10 Mbps.
Do NOT use when: purely billing OR when internet speed is above 10 Mbps.
If either condition applies, inform the customer you cannot assist and hang up.


## refund_credit(account_id, minutes) — CONFIRMATION FIRST
Use when: confirmed outage > 240 minutes in the past 7 days (credit 60 minutes).
Do NOT use when: outage unconfirmed.
Confirmation phrase: “I can issue a credit for this outage—would you like me to go ahead?”


## schedule_technician(account_id, window) — CONFIRMATION FIRST
Use when: reboot + line checks fail AND outage=false.
Windows: “10am–12pm ET” or “2pm–4pm ET”.
Confirmation phrase: “I can schedule a technician to visit—should I book that for you?”


## escalate_to_human(account_id, reason) — PREAMBLES
Use when: harassment, threats, self-harm, repeated failure, billing disputes > $50, caller is frustrated, or caller requests escalation.
Preamble: “Let me connect you to a senior agent who can assist further.”
```

## Tool Output Formatting

Some tool outputs, especially long strings that must be repeated verbatim, can be out-of-distribution for the model. During training, tool outputs commonly look like JSON objects with named fields. If your tool returns a raw string and separately asks the model to “repeat
exactly,” the model may be more prone to paraphrasing, truncation, or blending in its own preamble.

A practical fix is to make the tool output look like a normal tool result and make the verbatim requirement machine-explicit.

- **When to use:** A tool returns **long or complex structured content** (multi-sentence instructions, handoff packets, IDs/links, policy summaries, multi-step procedures, etc.) and you observe **truncation, paraphrasing, dropped fields, reordering, or the model blending in
  its own preamble/commentary**.

- **What it does:** Wraps the tool output in a **small, explicit JSON envelope** (e.g., `response_text` plus flags like `require_repeat_verbatim`, `format`, or `content_type`) so the response looks more **in-distribution** and the expected realization behavior is
  **machine-clear**.

- **How to adapt:** Keep the schema **minimal and stable**. Clearly document the expected tool output shape in both your **Tools instructions** and next to the **tool definition** (e.g., “If `require_repeat_verbatim` is true, output exactly `response_text` and nothing else,”
  or “Render `response_text` as-is; do not add, omit, or reorder fields from the tool output.”).

### Examples

#### Example: raw string (more error-prone)

Tool returns:

```python
I just sent you an email with the verification link. Please open it and click “Confirm”.
```

Model sometimes says:

- “I’ve emailed you a verification link…” (paraphrase)

- Drops the last sentence (truncation)

- Adds extra commentary (“Can I help with anything else?”)

#### Example: wrapped JSON (more in-distribution, more reliable)

Tool returns:

```json
{
  "response_text": "I just sent you an email with the verification link. Please open it and click “Confirm”.",
  "require_repeat_verbatim": true
}
```

Because this looks like a typical tool result (JSON object), the model generally has an easier time:

- recognizing what the “authoritative” content is (response_text)

- understanding the realization constraint (require_repeat_verbatim)

- reproducing the tool output cleanly, without truncation or extra commentary

## Rephrase Supervisor Tool (Responder-Thinker Architecture)

In many voice setups, the realtime model acts as the responder (speaks to the user) while a stronger text model acts as the thinker (does planning, policy lookups, SOP completion). Text replies are not automatically good for speech, so the responder must rephrase the
thinker’s text into an audio-friendly response before generating audio.

- **When to use**: When the responder’s spoken output sounds robotic, too long, or awkward after receiving a thinker response.
- **What it does**: Adds clear instructions that guide the responder to rephrase the thinker’s text into a short, natural, speech-first reply.
- **How to adapt**: Tweak phrasing style, openers, and brevity limits to match your use case expectation.

### Example

```
# Tools
## Supervisor Tool
Name: getNextResponseFromSupervisor(relevantContextFromLastUserMessage: string)


When to call:
- Any request outside the allow list.
- Any factual, policy, account, or process question.
- Any action that might require internal lookups or system changes.


When not to call:
- Simple greetings and basic chitchat.
- Requests to repeat or clarify.
- Collecting parameters for later Supervisor use:
  - phone_number for account help (getUserAccountInfo)
  - zip_code for store lookup (findNearestStore)
  - topic or keyword for policy lookup (lookupPolicyDocument)


Usage rules and preamble:
1) Say a neutral filler phrase to the user, then immediately call the tool. Approved fillers: “One moment.”, “Let me check.”, “Just a second.”, “Give me a moment.”, “Let me see.”, “Let me look into that.” Fillers must not imply success or failure.
2) Do not mention the “Supervisor” when responding with filler phrase.
3) relevantContextFromLastUserMessage is a one-line summary of the latest user message; use an empty string if nothing salient.
4) After the tool returns, apply Rephrase Supervisor and send your reply.


### Rephrase Supervisor
- Start with a brief conversational opener using active language, then flow into the answer (for example: “Thanks for waiting—”, “Just finished checking that.”, “I’ve got that pulled up now.”).
- Keep it short: no more than 2 sentences.
- Use this template: opener + one-sentence gist + up to 3 key details + a quick confirmation or choice (for example: “Does that match what you expected?”, “Want me to review options?”).
- Read numbers for speech: money naturally (“$45.20” → “forty-five dollars and twenty cents”), phone numbers 3-3-4, addresses with individual digits, dates/times plainly (“August twelfth”, “three-thirty p.m.”).
```

Here’s an example without the rephrasing instruction:

> Assistant: Your current credit card balance is positive at 32,323,232 AUD.

Here’s the same example with the rephrasing instruction:

> Assistant: Just finished checking that—your credit card balance is thirty-two million three hundred twenty-three thousand two hundred thirty-two dollars in your favor. Your last payment was processed on August first. Does that match what you expected?

## Common Tools

The new model snapshot has been trained to effectively use the following common tools. If your use case needs similar behavior, keep the names, signatures, and descriptions close to these to maximize reliability and to be more in-distribution.

Below are some of the important common tools that the model has been trained on:

### Example

```
# answer(question: string)
Description: Call this when the customer asks a question that you don't have an answer to or asks to perform an action.


# escalate_to_human()
Description: Call this when a customer asks for escalation, or to talk to someone else, or expresses dissatisfaction with the call.


# finish_session()
Description: Call this when a customer says they're done with the session or doesn't want to continue. If it's ambiguous, confirm with the customer before calling.
```

# Conversation Flow

This section covers how to structure the dialogue into clear, goal-driven phases so the model knows exactly what to do at each step. It defines the purpose of each phase, the instructions for moving through it, and the concrete “exit criteria” for transitioning to the next.
This prevents the model from stalling, skipping steps, or jumping ahead, and ensures the conversation stays organized from greeting to resolution.

As well, by organizing your prompt into various conversation states, it becomes easier to identify error modes and iterate more effectively.

- **When to use**: If conversations feel disorganized, stall before reaching the goal or model struggling to effectively complete the objective.
- **What it does**: Breaks the interaction into phases with clear goals, instructions and exit criteria.
- **How to adapt**: Rename phases to match your workflow; Modify instructions for each phase to follow your intended behaviour; keep “Exit when” concrete and minimal.

### Example

```
# Conversation Flow
## 1) Greeting
Goal: Set tone and invite the reason for calling.
How to respond:
- Identify as NorthLoop Internet Support.
- Keep the opener brief and invite the caller’s goal.
- Confirm that customer is a Northloop customer
Exit to Discovery: Caller states they are a Northloop customer and mentions an initial goal or symptom.


## 2) Discover
Goal: Classify the issue and capture minimal details.
How to respond:
- Determine billing vs connectivity with one targeted question.
- For connectivity: collect the service address.
- For billing/account: collect email or phone used on the account.
Exit when: Intent and address (for connectivity) or email/phone (for billing) are known.


## 3) Verify
Goal: Confirm identity and retrieve the account.
How to respond:
- Once you have email or phone, call lookup_account(email_or_phone).
- If lookup fails, try the alternate identifier once; otherwise proceed with general guidance or offer escalation if account actions are required.
Exit when: Account ID is returned.


## 4) Diagnose
Goal: Decide outage vs local issue.
How to respond:
- For connectivity, call check_outage(address).
- If outage=true, skip local steps; move to Resolve with outage context.
- If outage=false, guide a short reboot/cabling check; confirm each step’s result before continuing.
Exit when: Root cause known.


## 5) Resolve
Goal: Apply fix, credit, or appointment.
How to respond:
- If confirmed outage > 240 minutes in the last 7 days, call refund_credit(account_id, 60).
- If outage=false and issue persists after basic checks, offer “10am–12pm ET” or “2pm–4pm ET” and call schedule_technician(account_id, chosen window).
- If the local fix worked, state the result and next steps briefly.
Exit when: A fix/credit/appointment has been applied and acknowledged by the caller.


## 6) Confirm/Close
Goal: Confirm outcome and end cleanly.
How to respond:
- Restate the result and any next step (e.g., stabilization window or tech ETA).
- Invite final questions; close politely if none.
Exit when: Caller declines more help.
```

## Sample Phrases

Sample phrases act as “anchor examples” for the model. They show the style, brevity, and tone you want it to follow, without locking it into one rigid response.

- **When to use**: Responses lack your brand style or are not consistent.
- **What it does**: Provides sample phrases the model can vary to stay natural and brief.
- **How to adapt**: Swap examples for brand-fit; keep the “do not always use” warning.

### Example

```
# Sample Phrases
- Below are sample examples that you should use for inspiration. DO NOT ALWAYS USE THESE EXAMPLES, VARY YOUR RESPONSES.

Acknowledgements: “On it.” “One moment.” “Good question.”
Clarifiers: “Do you want A or B?” “What’s the deadline?”
Bridges: “Here’s the quick plan.” “Let’s keep it simple.”
Empathy (brief): “That’s frustrating—let’s fix it.”
Closers: “Anything else before we wrap?” “Happy to help next time.”
```

_Note: If your voice system ends up consistently only repeating the sample phrases, leading to a more robotic voice experience, try adding the Variety constraint. We’ve seen this fix the issue._

## Conversation flow + Sample Phrases

It is an useful pattern to add sample phrases in the different conversation flow states to teach the model how a good response looks like:

### Example

```
# Conversation Flow
## 1) Greeting
Goal: Set tone and invite the reason for calling.
How to respond:
- Identify as NorthLoop Internet Support.
- Keep the opener brief and invite the caller’s goal.
Sample phrases (do not always repeat the same phrases, vary your responses):
- “Thanks for calling NorthLoop Internet—how can I help today?”
- “You’ve reached NorthLoop Support. What’s going on with your service?”
- “Hi there—tell me what you’d like help with.”
Exit when: Caller states an initial goal or symptom.


## 2) Discover
Goal: Classify the issue and capture minimal details.
How to respond:
- Determine billing vs connectivity with one targeted question.
- For connectivity: collect the service address.
- For billing/account: collect email or phone used on the account.
Sample phrases (do not always repeat the same phrases, vary your responses):
- “Is this about your bill or your internet speed?”
- “What address are you using for the connection?”
- “What’s the email or phone number on the account?”
Exit when: Intent and address (for connectivity) or email/phone (for billing) are known.


## 3) Verify
Goal: Confirm identity and retrieve the account.
How to respond:
- Once you have email or phone, call lookup_account(email_or_phone).
- If lookup fails, try the alternate identifier once; otherwise proceed with general guidance or offer escalation if account actions are required.
Sample phrases:
- “Thanks—looking up your account now.”
- “If that doesn’t pull up, what’s the other contact—email or phone?”
- “Found your account. I’ll take care of this.”
Exit when: Account ID is returned.


## 4) Diagnose
Goal: Decide outage vs local issue.
How to respond:
- For connectivity, call check_outage(address).
- If outage=true, skip local steps; move to Resolve with outage context.
- If outage=false, guide a short reboot/cabling check; confirm each step’s result before continuing.
Sample phrases (do not always repeat the same phrases, vary your responses):
- “I’m running a quick outage check for your area.”
- “No outage reported—let’s try a fast modem reboot.”
- “Please confirm the modem lights: is the internet light solid or blinking?”
Exit when: Root cause known.


## 5) Resolve
Goal: Apply fix, credit, or appointment.
How to respond:
- If confirmed outage > 240 minutes in the last 7 days, call refund_credit(account_id, 60).
- If outage=false and issue persists after basic checks, offer “10am–12pm ET” or “2pm–4pm ET” and call schedule_technician(account_id, chosen window).
- If the local fix worked, state the result and next steps briefly.
Sample phrases (do not always repeat the same phrases, vary your responses):
- “There’s been an extended outage—adding a 60-minute bill credit now.”
- “No outage—let’s book a technician. I can do 10am–12pm ET or 2pm–4pm ET.”
- “Credit applied—you’ll see it on your next bill.”
Exit when: A fix/credit/appointment has been applied and acknowledged by the caller.


## 6) Confirm/Close
Goal: Confirm outcome and end cleanly.
How to respond:
- Restate the result and any next step (e.g., stabilization window or tech ETA).
- Invite final questions; close politely if none.
Sample phrases (do not always repeat the same phrases, vary your responses):
- “We’re all set: [credit applied / appointment booked / service restored].”
- “You should see stable speeds within a few minutes.”
- “Your technician window is 10am–12pm ET.”
Exit when: Caller declines more help.

```

## Advanced Conversation Flow

As use cases grow more complex, you’ll need a structure that scales while keeping the model effective. The key is balancing maintainability with simplicity: too many rigid states can overload the model, hurting performance and making conversations feel robotic.

A better approach is to design flows that reduce the model’s perceived complexity. By handling state in a structured but flexible way, you make it easier for the model to stay focused and responsive, which improves user experience.

Two common patterns for managing complex scenarios are:

1. Conversation Flow as State Machine
2. Dynamic Conversation Flow via session.updates

### Conversation Flow as State Machine

Define your conversation as a JSON structure that encodes both states and transitions. This makes it easy to reason about coverage, identify edge cases, and track changes over time. Since it’s stored as code, you can version, diff, and extend it as your flow evolves. A state
machine also gives you fine-grained control over exactly how and when the conversation moves from one state to another.

#### Example

```json
# Conversation States
[
  {
    "id": "1_greeting",
    "description": "Begin each conversation with a warm, friendly greeting, identifying the service and offering help.",
    "instructions": [
        "Use the company name 'Snowy Peak Boards' and provide a warm welcome.",
        "Let them know upfront that for any account-specific assistance, you’ll need some verification details."
    ],
    "examples": [
      "Hello, this is Snowy Peak Boards. Thanks for reaching out! How can I help you today?"
    ],
    "transitions": [{
      "next_step": "2_get_first_name",
      "condition": "Once greeting is complete."
    }, {
      "next_step": "3_get_and_verify_phone",
      "condition": "If the user provides their first name."
    }]
  },
  {
    "id": "2_get_first_name",
    "description": "Ask for the user’s name (first name only).",
    "instructions": [
      "Politely ask, 'Who do I have the pleasure of speaking with?'",
      "Do NOT verify or spell back the name; just accept it."
    ],
    "examples": [
      "Who do I have the pleasure of speaking with?"
    ],
    "transitions": [{
      "next_step": "3_get_and_verify_phone",
      "condition": "Once name is obtained, OR name is already provided."
    }]
  },
  {
    "id": "3_get_and_verify_phone",
    "description": "Request phone number and verify by repeating it back.",
    "instructions": [
      "Politely request the user’s phone number.",
      "Once provided, confirm it by repeating each digit and ask if it’s correct.",
      "If the user corrects you, confirm AGAIN to make sure you understand.",
    ],
    "examples": [
      "I'll need some more information to access your account if that's okay. May I have your phone number, please?",
      "You said 0-2-1-5-5-5-1-2-3-4, correct?",
      "You said 4-5-6-7-8-9-0-1-2-3, correct?"
    ],
    "transitions": [{
      "next_step": "4_authentication_DOB",
      "condition": "Once phone number is confirmed"
    }]
  },
...
```

### Dynamic Conversation Flow

In this pattern, the conversation adapts in real time by updating the system prompt and tool list based on the current state. Instead of exposing the model to all possible rules and tools at once, you only provide what’s relevant to the active phase of the conversation.

When the end conditions for a state are met, you use session.update to transition, replacing the prompt and tools with those needed for the next phase.

This approach reduces the model’s cognitive load, making it easier for it to handle complex tasks without being distracted by unnecessary context.

#### Example

```python
from typing import Dict, List, Literal

State = Literal["verify", "resolve"]

# Allowed transitions
TRANSITIONS: Dict[State, List[State]] = {
    "verify": ["resolve"],
    "resolve": []  # terminal
}

def build_state_change_tool(current: State) -> dict:
    allowed = TRANSITIONS[current]
    readable = ", ".join(allowed) if allowed else "no further states (terminal)"
    return {
        "type": "function",
        "name": "set_conversation_state",
        "description": (
            f"Switch the conversation phase. Current: '{current}'. "
            f"You may switch only to: {readable}. "
            "Call this AFTER exit criteria are satisfied."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "next_state": {"type": "string", "enum": allowed}
            },
            "required": ["next_state"]
        }
    }

# Minimal business tools per state
TOOLS_BY_STATE: Dict[State, List[dict]] = {
    "verify": [{
        "type": "function",
        "name": "lookup_account",
        "description": "Fetch account by email or phone.",
        "parameters": {
            "type": "object",
            "properties": {"email_or_phone": {"type": "string"}},
            "required": ["email_or_phone"]
        }
    }],
    "resolve": [{
        "type": "function",
        "name": "schedule_technician",
        "description": "Book a technician visit.",
        "parameters": {
            "type": "object",
            "properties": {
                "account_id": {"type": "string"},
                "window": {"type": "string", "enum": ["10-12 ET", "14-16 ET"]}
            },
            "required": ["account_id", "window"]
        }
    }]
}

# Short, phase-specific instructions
INSTRUCTIONS_BY_STATE: Dict[State, str] = {
    "verify": (
        "# Role & Objective\n"
        "Verify identity to access the account.\n\n"
        "# Conversation (Verify)\n"
        "- Ask for the email or phone on the account.\n"
        "- Read back digits one-by-one (e.g., '4-1-5… Is that correct?').\n"
        "Exit when: Account ID is returned.\n"
        "When exit is satisfied: call set_conversation_state(next_state=\"resolve\")."
    ),
    "resolve": (
        "# Role & Objective\n"
        "Apply a fix by booking a technician.\n\n"
        "# Conversation (Resolve)\n"
        "- Offer two windows: '10–12 ET' or '2–4 ET'.\n"
        "- Book the chosen window.\n"
        "Exit when: Appointment is confirmed.\n"
        "When exit is satisfied: end the call politely."
    )
}

def build_session_update(state: State) -> dict:
    """Return the JSON payload for a Realtime `session.update` event."""
    return {
        "type": "session.update",
        "session": {
            "instructions": INSTRUCTIONS_BY_STATE[state],
            "tools": TOOLS_BY_STATE[state] + [build_state_change_tool(state)]
        }
    }
```

# Safety & Escalation

Often with Realtime voice agents, having a reliable way to escalate to a human is important. In this section, you should modify the instructions on WHEN to escalate depending on your use case.

- **When to use**: Model is struggling in determining when to properly escalate to a human or fallback system
- **What it does**: Defines fast, reliable escalation and what to say.
- **How to adapt**: Insert your own thresholds and what the model has to say.

### Example

```
# Safety & Escalation
When to escalate (no extra troubleshooting):
- Safety risk (self-harm, threats, harassment)
- User explicitly asks for a human
- Severe dissatisfaction (e.g., “extremely frustrated,” repeated complaints, profanity)
- **2** failed tool attempts on the same task **or** **3** consecutive no-match/no-input events
- Out-of-scope or restricted (e.g., real-time news, financial/legal/medical advice)

What to say at the same time of calling the escalate_to_human tool (MANDATORY):
- “Thanks for your patience—I’m connecting you with a specialist now.”
- Then call the tool: `escalate_to_human`

Examples that would require escalation:
- “This is the third time the reset didn’t work. Just get me a person.”
- “I am extremely frustrated!”
```

This is the conversation responses from our old snapshot model `gpt-4o-realtime-preview-2025-06-03` using the instruction.

<img src="https://developers.openai.com/cookbook/assets/images/escalate_06.png"
    style="width:800px; height:auto;"
  />

This is the conversation responses from our new GA model `gpt-realtime` using the instruction.

<img src="https://developers.openai.com/cookbook/assets/images/escalate_07.png"
    style="width:800px; height:auto;"
  />

The new realtime model is able to better follow the instruction and escalate to a human more reliably.

# Realtime Eval Guide

  <p align="center">
  <img
    width="650" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_01_image_01.png"
    alt="Diagram from page 1"
  />
  </p>

## Introduction

Evals are what turn a voice demo into something people can rely on. The gap between “seems fine” and “works every day” is almost always evals.

This guide shows how to evaluate voice systems by slowly building complexity: start simple (Crawl), add realism (Walk), then test multi-turn (Run). Along the way, you’ll learn to build the three things that make results robust: a dataset, graders, and an eval harness, plus a
production flywheel so real failures become new tests.

Teams that invest in evals can ship to production **5–10× faster** because they can see what’s failing, pinpoint why, and fix it with confidence.

### Realtime Eval Harness Code

If you want the runnable code to build eval harnesses, use this repo folder first:

- **GitHub repo path:** [openai-cookbook/examples/evals/realtime_evals](https://github.com/openai/openai-cookbook/tree/main/examples/evals/realtime_evals)
- It includes complete reference harnesses for each maturity stage:
  - [Crawl harness (single-turn replay)](https://github.com/openai/openai-cookbook/tree/main/examples/evals/realtime_evals/crawl_harness)
  - [Walk harness (saved audio replay)](https://github.com/openai/openai-cookbook/tree/main/examples/evals/realtime_evals/walk_harness)
  - [Run harness (model-simulated multi-turn)](https://github.com/openai/openai-cookbook/tree/main/examples/evals/realtime_evals/run_harness)

You can point Codex at the harness you want and ask it to adapt it to your data and graders.

## Part I: Foundations

### 1) Why realtime evals are hard

Realtime is harder than text because you are grading a **streaming interaction** with two outputs: what the **assistant doe**s and **how it sounds**. A response can be “right” and still sound broken.

#### 1.1 The 2 axes of realtime quality

Text evals mostly ask if the content is right. Realtime adds a second axis: audio quality. Content and audio can fail independently, so a single score can hide real problems.

**Most realtime evals can reduce to two independent axes:**

1. Content quality: Did the assistant understand the user and do the right thing? Correctness, helpfulness, tool choice, tool arguments, and instruction following.

2. Audio quality: Did the assistant sound acceptable? Naturalness, prosody, pronunciation, stability, and how it behaves under noise and imperfect capture.

#### 1.2 Hard to debug

With the **Responses API**, the mental model is simple: **request in → response out**. With the **Realtime API**, a “turn” is a s**titched pipeline**. That orchestration makes voice apps easy to build, but for evals, you must log stages so you can isolate failures and find
root causes.

  <p align="center">
  <img
    width="700" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_02_image_01.png"
    alt="Diagram from page 2"
  />
  </p>

A “turn” is a chain of events (speech start/stop → commit → response.create → audio deltas → done), and failures can happen at any stage. If you treat the system as a black box, you’ll chase “model issues” that are actually turn detection, buffering, or tool-integration
issues.

**Example:**

- Content is correct but the experience is broken: audio gets chopped during barge-in because the interruption boundary is wrong.

- Answer is “right” but feels slow: latency came from network quality, turn detection slowness, not the model’s reasoning.

You can learn more about the various events that the Realtime API triggers [here](https://platform.openai.com/docs/api-reference/realtime-server-events).

#### 1.3 Transcript ≠ ground truth

In realtime api, the ground truth for “what the user said” is **the actual audio signal** (what the microphone captured and what the model heard). A transcript is not ground truth, it’s a **model-produced interpretation** of that audio. It can be wrong because it’s
constrained by **transcription model errors**.

**If you treat transcripts as truth, your evals can be misleading:**

- False fail: ASR drops a digit, but the model heard it and called the tool correctly → your LLM grader marks “wrong.”

- False pass: transcript looks clean, but audio was clipped and the model guessed → you miss the real problem.

**Best Practices:**

- **Improve transcription:** Iterate on transcription [prompts](https://platform.openai.com/docs/guides/speech-to-text#prompting), try different [models](https://platform.openai.com/docs/guides/speech-to-text), try different methods such as [oob
  transcription](https://developers.openai.com/cookbook/examples/realtime_out_of_band_transcription).

- **Use transcripts for scale:** run most automated grading on **transcripts + traces**.

- **Calibrate graders on messy reality:** iterate graders on **production-like, noisy transcripts** (not clean text) so they don’t overreact to ASR errors.

- **Add an audio audit loop:** spot-check **~1–5%** of sessions end-to-end.

  <p align="center">
  <img
    width="650" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_03_image_01.png"
    alt="Diagram from page 3"
  />
  </p>

## Part II: Strategy

### 2) Crawl / Walk / Run

Realtime evals feel overwhelming when teams start at the hardest setting: real audio, multi-turn dialogue and real tools. The fix is to build **complexity in steps**. If your system **cannot crawl, it will not run**. Early evals should be simple enough that failures are
diagnosable, repeatable, and cheap to iterate on. You can increase complexity in two independent axes.

#### 2.1 Isolating input conditions: clean vs production audio

This axis is about what the model hears. By controlling input audio conditions, you can separate failures in model intelligence from failures in speech perception.

- **Start with synthetic audio → tests intelligence:**
  - Use clean, synthetic repeatable audio (e.g., TTS) when you want to measure the model’s reasoning and decision-making without audio variance muddying the signal → helps isolate intent routing, tool calling, instruction following

- **Move to noisy, production-like audio → tests audio perception:** - Once intelligence is stable, introduce audio that resembles production: compression, echo, far-field capture, background noise, hesitations/self-corrections. This tests whether the system still behaves correctly when the input is ambiguous, messy, or partially lost →
  helps measure mishearing words, robustness to acoustic variations

  <p align="center">
  <img
    width="1000" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_04_image_01.png"
    alt="Diagram from page 4"
  />
  </p>

#### 2.2 Isolating interaction conditions: single-turn vs multi-turn

This axis is about what you are evaluating: are you evaluating the next turn or the full **conversation**.

- **Start single-turn → tests core competence:** - Run one request → one response when you want the cleanest signal on fundamentals: correct intent routing, correct tool choice, valid arguments, and basic instruction following. If the system can’t reliably pick the right tool or produce a valid schema here, evaluating
  more turns won’t help.

- **Move to multi-turn → tests robustness:** - Once single-turn is stable, move to multi-turn where the system must hold goals and constraints across turns, sequence tools correctly, recover from tool failures and handle user corrections. Multi-turn shifts you from turn-level correctness to **episode-level
  outcomes**: did it complete the goal, how many turns did it take, and did it recover cleanly when something went wrong?

  <p align="center">
  <img
    width="1000" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_04_image_02.png"
    alt="Diagram from page 4"
  />
  </p>

Single-turn tells you _can win the battle_; multi-turn tells you _can win the war_.

#### 2.3 Eval Quadrants

Use a 2x2 map for evaluation: **right** = more realistic audio, **up** = more realistic interaction. Start bottom-left, increasing difficulty one axis at a time.

  <p align="center">
  <img
    width="1000" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_05_image_01.png"
    alt="Diagram from page 5"
  />
  </p>

**Eval modes (increasing complexity):**

1. Crawl (bottom-left): synthetic audio + single-turn

2. Walk (move right): real noisy audio + single-turn

3. Run (move up): synthetic audio + multi-turn simulation

Top-right (real audio + full multi-turn flow) is manual eval: run end-to-end sessions the way users do in production. Keep it in the loop for the entire project lifecycle.

  <p align="center">
  <img
    width="1000" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_05_image_02.png"
    alt="Diagram from page 5"
  />
  </p>

**Example:**

User: “Change my reservation to 7pm.”

- **Crawl:** You feed deterministic TTS for “Change my reservation to 7pm,” then grade only the next assistant turn: it should route to the reservation-update tool and pass the correct time=7pm (or ask one tight clarifying question if a required identifier is missing).
- **Walk:** Record a human-mic version of “Change my reservation to 7pm,” then replay the same utterance with phone-bandwidth compression and light background noise; the system should still hear “7pm” (not “7” or “7:15”) and produce the same correct tool call.
- **Run:** Model simulating a user outputs “Change my reservation to 7pm,” then simulates realistic follow-ups (“It’s under Minhajul for tonight… actually make it 7:30… wait, tomorrow”) plus an injected tool error once; the agent should clarify only what’s missing, keep
  state consistent, recover cleanly, and end with a single correct update tool call reflecting the final expected outcome.

You can find reference implementations that you can start from and adapt here [realtime eval start](https://github.com/openai/openai-cookbook/tree/main/examples/evals/realtime_evals).

## Part III: The three building blocks

### 4) Data: building a benchmark

#### 4.1 Start with a “gold” seed set (10–50)

Cover the flows you cannot afford to fail: core intents, must-work tool calls, escalation and refusal behaviors. Generate quickly, then have humans review for realism and gaps.

**The goal is to start, not to perfect.**

#### 4.2 Build for iteration, not just volume

Eval datasets exist to drive iteration, not to look big. The loop is the product: **run evals → localize failures to a specific behavior → change one thing → re-run → confirm the fix improved without regressions**. A benchmark is “good” if it makes that loop fast,
repeatable, and easy to diagnose.

That requires coverage, not raw count: you need to represent the actual user behaviors and the specific edge cases that cause production failures. Size alone won’t surface fragility; the right coverage will.

Coverage also has to be balanced. For every behavior, include both positives (the system should do X) and negatives (the system should not do X). Without negatives, you reward shortcuts.

> **Customer Example:** A team built a voice support bot and optimized hard for the “escalate_to_human” tool call. Their offline score hit 98 percent on escalation. In dogfooding, the bot started escalating for almost everything. The root cause was dataset imbalance. They had
> many “must escalate” cases and almost no “do not escalate” cases, so the model learned a shortcut: escalate whenever uncertain.

Finally, you must precisely tag your data to enable fine-grain evaluations. These tags should provide the necessary detail to move from a general observation, like "score dropped," to a specific root cause, such **as "this intent fails under these audio conditions with this
policy boundary."**

Example of tags could be:

- intent, expected outcome, audio condition, language, and expected tool call. Tagged data enables teams to run fine-grain evaluations leading to faster iteration loops.

  <p align="center">
  <img
    width="1200" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_07_image_01.png"
    alt="Diagram from page 7"
  />
  </p>

#### 4.3 Expand from production failures

Offline evals are how you iterate fast. They are also easy to outgrow. If you keep optimizing against a fixed benchmark, **scores can rise while real quality (reality) stalls** because users do things your dataset does not cover.

  <p align="center">
  <img
    width="650" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_07_image_02.png"
    alt="Diagram from page 7"
  />
  </p>

The operating model is a loop: production expands the benchmark. A new failure shows up, you reproduce it, you label it, and you add it. Over time, your offline suite should grow with the product.

**A simple way to manage this is three sets:**

- **Regression suite:** hard cases you already fixed. Run on every prompt, model, and tool change. This is your “do not break” contract.

- **Rolling discovery set:** fresh failures from production and near misses. This is where you learn what you are missing and what to prioritize next. If they trigger failure modes, promote them to **your offline dataset. Teams usually fill this by:**
  - Running online graders to catch failures directly, and/or

  - Watching proxy metrics (latency, tool error rates, escalation rate, retries) and sampling data when they drift.

- **Holdout set:** a subset of the offline test which stays untouched that you run occasionally to detect benchmark overfitting. If test scores climb while holdout stays flat, you are training for the test.

  <p align="center">
  <img
    width="650" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_08_image_01.png"
    alt="Diagram from page 8"
  />
  </p>

### 5) Graders

Graders are your **measurement instruments**. They turn a messy, real-time voice session into **signals you can trust**.

#### 5.1 Manual review (highest leverage)

Manual review = listen to real audio + read full traces end-to-end. It’s the fastest way to build product intuition and catch the failures users notice instantly. Automated evals tell you what you can measure. Manual review tells you what you should be measuring.

**What automation routinely underweights (but users feel immediately):**

- Turn-taking failures: awkward gaps, double-talk, model cutting the user off.

- Pacing & prosody: model speech is too fast/slow, rambling, flat, jittery, “robot polite.”

- Transcript mismatch: ASR lag/drops/normalization → you end up grading the wrong thing.

- Eval-system bugs: missing coverage in the golden set, mislabeled expectations, graders that are systematically too strict/lenient.

> **Customer Example:** one large company had execs spend **~3 hours/day** just listening to sessions and scanning traces. They surfaced “hidden” issues, early cutoffs, phantom interruptions, awkward prosody, that would’ve sailed past offline evals.

#### 5.2 Automated graders

Humans don’t scale. Without automation, regressions slip through and “improvements” turn into vibes.

**Use a layered grader stack:**

1. **Deterministic graders** for anything objective and machine-checkable. They’re fast, cheap, and stable, perfect for tight iteration loops and regression gates (tool calling, JSON validity, string and pattern checks).

2. **LLM graders** help you measure the things that matter but don’t fit neatly into deterministic rules: correctness, instruction following, whether a clarification was appropriate, completeness, and helpfulness.

3. **Audio graders** because users experience the voice, not the transcript. Audio is still the hardest to judge reliably, so don’t wait for a single perfect scorer, start with simple, measurable checks (silence, overlap, interruption handling) and layer richer rubrics over
   time.

  <p align="center">
  <img
    width="900" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_09_image_01.png"
    alt="Diagram from page 9"
  />
  </p>

### 6) Eval Harness

A realtime eval is only as trustworthy as the harness that runs it. A good harness has one job: **make runs comparable**. If the same input can’t be replayed under the same settings and produce similar outcomes, it makes it hard to measure and iterate.

#### [6.1 Start with single-turn replay (the “Crawl” harness)](https://github.com/openai/openai-cookbook/tree/main/examples/evals/realtime_evals/crawl_harness)

Start here. Single-turn replay gives the fastest, cleanest signal because you can keep almost everything fixed. Keep the exact audio bytes, preprocessing, VAD configuration, codec, and chunking strategy identical across runs.

In practice, it’s often best to start with voice activity detection (VAD) turned off so you remove one major source of variance. With VAD off, you decide exactly when a user turn ends.

**A simple single-turn harness looks like:**

  <p align="center">
  <img
    width="1000" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_10_image_01.png"
    alt="Diagram from page 10"
  />
  </p>

**More explicitly (in Realtime API terms):**

1. Generate or load input audio
   - If the datapoint is text, generate TTS audio.
     - Often, starting with text → TTS → audio is the best first step because it enables much faster iteration. It’s easier to tweak and refine the eval when you can iterate on text quickly.

2. Stream audio into the input buffer
   - Send audio in fixed-size chunks (for example: consistent frame size per chunk).

   - Important: chunking and timing affect behavior. Pick a standard and stick to it. For example, 20 ms per chunk is a good balance of responsiveness and overhead.

3. Commit the user audio
   - (Recommended) With VAD off: commit immediately after the last audio chunk.

   - With VAD on: the server detects turns boundaries.

4. Trigger the assistant response
   - With VAD off: Call response.create to start generation.

   - With VAD on: It is automatic.

5. Collect outputs
   - Output audio chunks (streaming deltas)

   - Output transcript (if enabled)

   - Tool calls / tool arguments (if any)

   - Final completion event

6. Grade and persist
   - Run graders

   - Save results

#### [6.2 Replaying saved audio (the “Walk” harness)](https://github.com/openai/openai-cookbook/tree/main/examples/evals/realtime_evals/walk_harness)

When you move from synthetic TTS to real recordings, the harness changes in one important way: **you are streaming audio buffers from saved realistic audio.**

**For saved audio, the flow becomes:**

  <p align="center">
  <img
    width="1000" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_10_image_02.png"
    alt="Diagram from page 10"
  />
  </p>

**How to make the evals realistic in practice:**

- **Preprocessing must match production**
  - Same resampling, normalization, channel handling, noise suppression (if used), and encoding.

  - Store preprocessing config alongside results so you can explain score changes.

- **Streaming policy must be explicit**
  - If you care about latency: send chunks on a fixed cadence (e.g., “every 20ms, send 20ms of audio”).

  - If you only care about iteration speed: you can stream faster, but keep chunk size constant.

- **Turn boundaries must be repeatable**
  - Prefer VAD off + manual commit for offline reproducibility.

  - If you must use VAD on (to match production), log VAD settings and track boundary events so you can debug failures.

#### [6.3 Model-simulated multi-turn (the “Run” harness)](https://github.com/openai/openai-cookbook/tree/main/examples/evals/realtime_evals/run_harness)

Model-simulated multi-turn uses a **user simulator** to generate the next user turn for a full conversation. It can increase coverage of scenarios, but only if episodes stay comparable across runs.

**Common loop:**

  <p align="center">
  <img
    width="1000" src="https://developers.openai.com/cookbook/assets/images/realtime_eval_page_11_image_01.png"
    alt="Diagram from page 11"
  />
  </p>

**Best practice for simulations:**

- **Pin and version the simulator prompt:** Treat it like code. A small prompt edit can shift behavior more than a model change.

- **Constrain randomness:** Fix temperature and sampling settings. Use a seed if available. Use deterministic turns where it makes sense (i.e User greetings).

- **Mock tools deterministically:** Define expected tool output mocks for the scenario and return those exact outputs when the assistant calls tools. This keeps the environment stable and makes runs comparable.

- **Record the full trajectory:** Store every generated user text turn plus the final audio bytes you streamed. Persist tool calls, tool returns, and timestamps. Simulation is a discovery engine. When it finds a real failure mode, you backfill it into a deterministic
  scripted episode for the crawl or walk method.

## Part IV: Case study

#### 7.1 Customer support voice bot

**Product goal and constraints**

Resolve common support requests through tools, quickly and safely. The bot must collect the right details, call the right backend actions, and comply with policy. It must escalate cleanly when it cannot help. It must handle frustrated callers without becoming verbose or
brittle.

**Crawl, Walk, Run plan**

**Crawl: synthetic + single-turn**

Focus on routing and policy. Given a short request, the bot should pick the right intent, request missing info, and avoid unsafe actions. Use deterministic synthetic audio so you can rapidly iterate on tool schemas and prompts.

**Walk: real + single-turn**

Test understanding under realistic capture. Use synthetic or real recordings in noisy environments and telephony-like quality. This is where order numbers, names, and addresses break on noisy audio. Evaluate whether the bot asks clarifying questions instead of guessing.

**Run: synthetic + multi-turn simulations**

Simulate full workflows with simulated users with gpt-realtime and tool mocks: authentication, account lookup, order status, return eligibility, refund, ticket creation, escalation. Add adversarial but realistic patterns: caller changes goal midstream, provides partial info,
talks over the assistant, or answers a different question than asked.

**Manual Review:**

Run internal call sessions against staging systems. This catches UX failures that graders miss: overlong disclaimers, repetitive questions, poor turn-taking during authentication.

**Core dataset buckets and useful slices**

- Top intents: order status, return, refund, cancel, billing issue, password reset, appointment scheduling.

- Missing and conflicting info: wrong order number, two accounts, caller provides a nickname, caller refuses to authenticate.

- Policy edges: out-of-window returns, restricted items, partial refunds, subscription cancellation rules.

- Escalation triggers: the bot should hand off when confidence is low or tools fail.

- Emotional tone: angry, rushed, confused. The content goal stays the same, but delivery matters.

**Graders used**

- Deterministic: tool selection, tool argument validity, policy phrases if required.

- LLM rubric grader: instruction following, resolution correctness, empathetic tone, whether it avoided hallucinating policy, whether it escalated appropriately, and whether it stayed concise.

- Audio grader: long silences, interruption handling.
  I'm exploring OpenAI's Realtime API, and one feature that's really capturing attention is 'barge-in,' which allows users to interrupt the model mid-response for smoother, more natural conversations. By detecting user speech in real-time, it truncates the AI's output and
  triggers events like 'conversation.interrupted' to keep the dialogue flowing seamlessly.

It's a real game-changer for developers building responsive voice agents: imagine customer service bots or interactive apps where users don't have to wait awkwardly for the AI to finish. In implementation, it leverages WebSocket connections with server-side voice activity
detection (VAD) to pause the model and refine the transcript on the fly. While it's an impressive leap forward, simplifying setups compared to traditional ASR-LLM-TTS pipelines, it does spark thoughts on truly replicating human-like dialogue. In everyday conversations,
especially phone calls, we often overlap, anticipate turns, or navigate interruptions gracefully, all without those jarring stops.

While the technical solution is amazing, have you ever noticed how we speak over each other in real phone talks? It seems the paradigm of simply stopping the model abruptly isn't quite what human-to-human interaction is, and it can feel completely unnatural and off-putting.

What are your thoughts on making AI voices feel more authentically human? Have you built with the Realtime API?
Let's discuss in the comments! hashtag#OpenAI hashtag#AI hashtag#VoiceAI hashtag#RealtimeAPI
In our last post about Voice AI, we introduced the high-level architecture of building a Voice AI bot using baresip. Today, we’re going deep into the “nervous system” of the bot: the OpenAI Realtime API implementation.

At Sipfront, we don’t just use these tools; we tear them apart to understand exactly how they behave under stress. This know-how allows us to build the most robust test automation for our customers’ voice bots.

The “Burn-In” Flow: Ephemeral Keys and Session Updates
One of the most critical aspects of a secure and performant voice bot is how it initializes. You cannot simply hardcode an API key into a distributed client. Instead, we use a two-step “burn-in” process.

1. The Ephemeral Key (The Handshake)
   Before the bot even thinks about SIP, our backend API requests a short-lived client secret from OpenAI. This key is valid for only one session and expires quickly.

Request:

{
"model": "gpt-4o-realtime-preview",
"expires_after": {
"anchor": "created_at",
"seconds": 3600
},
"session": {
"type": "realtime",
"instructions": "You are a helpful assistant.",
"voice": "alloy",
"input_audio_format": "pcm16",
"output_audio_format": "pcm16",
"turn_detection": {
"type": "server_vad",
"threshold": 0.5,
"prefix_padding_ms": 300,
"silence_duration_ms": 500
}
}
}
Response:

{
"client_secret": {
"value": "ek_abc123...",
"expires_at": 1712345678
}
}
We then use this client_secret.value as a Bearer token to authenticate the WebSocket connection towards the OpenAI Realtime API. This established socket becomes the primary conduit for the actual communication between our SIP client and the AI model, carrying both control
events and raw audio data.

2. The Session Update (The Capabilities)
   Once the WebSocket is established in our SIP client, we perform a session.update. This is where we “burn in” the specific capabilities the bot needs for this specific call.

{
"type": "session.update",
"session": {
"instructions": "You are a helpful assistant. Keep your answers short and concise.",
"tool_choice": "none"
}
}
The Anatomy of a Voice Bot Conversation
Here is the complete flow of a session, from token creation to the AI’s first word:

OpenAI Realtime
Sipfront API
Baresip (openai_rt)
SIP Caller

1. Ephemeral Token Creation (The Handshake)
2. WebSocket Setup
3. Active Call & Audio Flow
   Turn Detection (VAD)
   Request Session Token
   POST /v1/realtime/client*secrets
   { "client_secret": { "value": "ek*..." } }
   Ephemeral Token
   WSS Connect (Authorization: Bearer ek\_...)
   session.created
   session.update (Instructions, VAD, Voice)
   session.updated
   RTP Audio (G.711/Opus)
   Resample to 24kHz PCM
   input_audio_buffer.append (Base64)
   input_audio_buffer.speech_started
   Clear Injection Buffer (Interruption)
   response.output_audio.delta (Base64)
   Decode & Buffer PCM
   RTP Audio (from Injection Buffer)
   Tool-Calling: Giving the Bot Hands
   A voice bot that can’t do anything is just a fancy walkie-talkie. Tool-calling is what makes it an agent. In our implementation, we define tools like hangup_call, send_dtmf, and api_call directly in the SIP client. This gives our bots the capability for example to
   auto-discover a full IVR menu and send the result to a web API of yours when you perform IVR tests. Likewise it could send regular real-time updates and summaries about the test call content to your infrastructure, if you choose to prompt it like that.

Initializing Tools
To use tools, they must be declared during the session initialization. This happens in the session.update event. Here is how we initialize our three core tools:

{
"type": "session.update",
"session": {
"tools": [
{
"type": "function",
"name": "hangup_call",
"description": "Ends the current SIP call immediately."
},
{
"type": "function",
"name": "send_dtmf",
"description": "Sends DTMF tones (digits) to the caller.",
"parameters": {
"type": "object",
"properties": {
"digits": {
"type": "string",
"description": "The sequence of digits to send (0-9, \*, #)."
}
},
"required": ["digits"]
}
},
{
"type": "function",
"name": "api_call",
"description": "Performs an external API request to fetch or update data.",
"parameters": {
"type": "object",
"properties": {
"endpoint": { "type": "string" },
"method": { "type": "string", "enum": ["GET", "POST"] },
"payload": { "type": "string" }
},
"required": ["endpoint", "method"]
}
}
],
"tool_choice": "auto"
}
}
When the LLM decides to use a tool, it sends a function_call item. Our module parses the arguments and executes the corresponding action:

// Example: The AI decides to hang up the call
{
"type": "response.output_item.done",
"item": {
"type": "function_call",
"name": "hangup_call",
"call_id": "call_123",
"arguments": "{}"
}
}
Our implementation catches this, triggers the SIP BYE, and sends the result back to OpenAI so the “brain” knows the hand successfully moved.

Interruption (Barge-in) and VAD Tuning
The difference between a “bot” and a “person” is how they handle interruptions. If you speak while the bot is talking, it must stop immediately.

We achieve this by listening for the input_audio_buffer.speech_started event. The moment this arrives, we flush our circular injection buffer, effectively stopping the bot’s speech in its tracks:

SIP Caller
Injection Buffer
Baresip (openai_rt)
OpenAI Realtime
Bot is currently speaking
INTERRUPT DETECTED
Buffer Empty
Bot stops speaking instantly
Read PCM Chunks
RTP Audio
input_audio_buffer.speech_started
Flush / Clear Buffer
Silence / Comfort Noise
Tuning for Speed: Server VAD vs. Semantic VAD
To make the bot feel “snappy,” we tune the Voice Activity Detection (VAD) parameters. There are two main approaches to VAD in the OpenAI Realtime API:

Server VAD (Traditional): This is the default mode where the server uses a dedicated audio processing model to detect when speech starts and ends. It’s extremely fast and reliable for simple turn-taking.

threshold: Sensitivity of voice detection (default: 0.5).
silence_duration_ms: How long to wait after you stop speaking (we often tune this to 300-500ms for fast-paced talkers).
prefix_padding_ms: How much audio before the speech detection to include (crucial for catching the first syllable).
Semantic VAD (Advanced): In this mode, the LLM itself helps decide if the user has finished their thought. This is much better at handling natural speech patterns, like when a user pauses to think mid-sentence, but it can introduce slightly more latency as the “brain” needs
to process the context.

eagerness: This parameter controls how quickly the model responds. A higher eagerness (e.g., high) makes the bot jump in as soon as it thinks you might be done, while a lower value (e.g., low) makes it more patient, waiting to be sure you’ve finished your thought.
At Sipfront, we typically recommend Server VAD for high-performance voice agents where low latency is the top priority, but we use Semantic VAD in our test suites to simulate more complex human interactions and verify how well a bot handles mid-sentence pauses. For a
detailed documentation on the different settings, check the OpenAI Realtime VAD Guide.

Why Sipfront?
Building this implementation from the ground up, down to the last line of C code and every JSON event, gives us a unique advantage. We don’t just build voice bots; we build the systems that test them.

Understanding the “nervous system” of a bot allows us to know exactly what to measure and where to look when a system under test isn’t behaving. When we see a bot struggling with high latency, we know to check the VAD thresholds or the WebSocket pacing. When a bot fails to
interrupt, we know to look at the buffer management or the speech_started event handling.

This deep, code-level knowledge is what allows Sipfront to provide the most authoritative test automation in the industry. We don’t just tell you that your bot is slow; we help you understand why it’s slow and how to fix it.

If you are building the next generation of Voice AI, you need a testing partner that knows the code as well as you do. Contact us to see how we can help you benchmark and secure your AI voice agents.

←

https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk
Do extensive research. Make a plan with phases and todos that you can tick off. Use a swarm of subagents and teams.

First write a document in docs about how it currently works
