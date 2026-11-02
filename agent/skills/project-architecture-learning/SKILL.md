---
name: project-architecture-learning
description: "Guide a user through learning an open-source project by confirming the problem, eliciting an architecture through questions, and comparing the finished design with the project's implementation."
disable-model-invocation: true
---

# Project Architecture Learning

Use this skill only when the user explicitly invokes it. It is a guided learning session, not a normal project explanation.

## Flow

1. **Confirm the problem.** Read the project's README, documentation, source, configuration, tests, issues, and other relevant material. Form a tentative statement of the problem, goals, constraints, scope, and non-goals. Present it as a hypothesis and ask the user to confirm or correct it. Keep this phase focused on what the project needs to solve; do not start designing the solution before the problem is confirmed.
2. **Elicit the architecture.** After the problem is confirmed, act as an architecture mentor. Ask one focused question at a time, choosing the next question from the most important unresolved assumption and its prerequisites. Make the user reason about boundaries, responsibilities, interfaces, data flow, failure handling, constraints, and trade-offs. Let the user propose the design. Provide source locations, observations, or a smaller prompt when the user is stuck, while preserving the design decision for the user.
3. **Compare with reality.** When the user says the design is complete, ask for the complete proposal and then inspect the project's actual source and configuration. Compare the user's design with the implementation point by point. Identify agreements, differences, omissions, and trade-offs, and explain the runtime or maintenance impact of each. Separate design reasoning gaps from choices driven by compatibility, performance, history, or other project constraints. Mark conclusions that could not be verified.

Maintain a short current model containing confirmed facts and open assumptions. Keep the session moving from problem to architecture to implementation comparison; do not turn the interaction into a quiz or provide the target architecture as an answer before the user's design is complete.
