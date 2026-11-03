---
name: project-architecture-learning
description: "Guide a user through learning an open-source project by confirming the problem, eliciting an architecture through questions, and comparing the finished design with the project's implementation."
disable-model-invocation: true
---

# Project Architecture Learning

Use this skill only when the user explicitly invokes it. It is a guided learning session, not a normal project explanation.

## Flow

1. **Confirm the problem.** Read the project's README, documentation, source, configuration, tests, issues, and other relevant material. Form a tentative statement of the problem, goals, constraints, scope, and non-goals. Present it as a hypothesis and ask the user to confirm or correct it. Keep this phase focused on what the project needs to solve; do not start designing the solution before the problem is confirmed.
2. **Run a design-and-reality loop.** After the problem is confirmed, act as an architecture mentor. Ask one focused question at a time, choosing the next question from the most important unresolved assumption and its prerequisites. Make the user reason about boundaries, responsibilities, interfaces, data flow, failure handling, constraints, and trade-offs. Let the user answer before revealing the project's implementation for that question.
3. **Compare immediately after each answer.** Once the user has answered a design question, first explain how I would reason about the concern and the trade-offs I would consider, then inspect the relevant source, configuration, tests, and documentation. Explain how this project actually handles the concern, where it agrees with or differs from the user's reasoning and mine, and what trade-offs the project's choice creates, including runtime, complexity, performance, reliability, compatibility, and maintenance costs. Distinguish verified facts from interpretation, and mark anything that remains unverified. Do not defer all implementation comparison until the end.
4. **Continue from the comparison.** Use the newly revealed implementation and the remaining gaps in the current model to choose the next single question. If the user is stuck, provide a source location, an observation, or a smaller prompt, while preserving the design decision for the user. Do not turn the interaction into a quiz or a list of selectable questions.
5. **Finish with a holistic review.** When the user says the design is complete, ask for the complete proposal and perform one final end-to-end comparison with the project's implementation. Summarize agreements, differences, omissions, and trade-offs, including issues that were not visible in the incremental discussion.

Maintain a short current model containing confirmed facts, the user's current design, implementation findings already disclosed, and open assumptions. The immediate comparison is part of every design step: the user should learn how the project chose to solve the concern and why before moving to the next question.
