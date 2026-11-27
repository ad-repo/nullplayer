---
name: pre-pr-review
description: The procedure every PR goes through before it opens. A fresh reviewer agent reviews the whole branch; the user decides which findings to fix, or delegates that to a second fresh implementer agent whose decisions and fixes the author agent then judges and tests; and the PR description records every finding. Use before opening any PR, when asked to "land the plane", or when the user says to have a fresh agent review, triage or implement review findings.
---

# Pre-PR Review

Every PR is preceded by a code-quality review of the whole branch, and a PR whose description lacks
the **Code quality review** section below is not ready to open. The review's lens is the
`thermo-nuclear-code-quality-review` skill; this skill is the process around it. The rest of the PR
description (issue, evidence, proof of testing, a How to test comment) is
`CONTRIBUTING.md` § *Required PR Description*.

Terms: the *author agent* is the agent that wrote the change; *the user* is the person opening the
PR.

## 1. Run the review in a fresh agent

The author agent never runs the review itself: it reads its own change through the decisions it
already made and talks itself out of the findings. Run it in a fresh agent with no context from
writing the change: in Claude Code, a new subagent (not a fork, which inherits the conversation) or
a new session; with another tool, a new chat.

Give it only the `thermo-nuclear-code-quality-review` skill and the scope: the whole branch against
`origin/main` (`git fetch origin` first, never local `main`), plus uncommitted changes. Give no
account of what the change does or why it was built that way. It reviews only and changes nothing.

## 2. Decide what gets addressed

The author agent does not decide. One of two routes, and only the user picks the second.

### The user decides (the default)

Hand every finding to the user exactly as returned, applying none of them. The user accepts or
rejects each one; only then does the author agent fix the accepted ones.

### The user delegates the decisions to an implementer agent

The user may hand the decisions to a fresh *implementer agent* ("have a fresh agent decide what to
address and implement the fixes"). The author agent never takes this route on its own.

1. **The implementer decides and fixes.** Start a second fresh agent, a new subagent and not a fork,
   as the reviewer was. Give it the findings verbatim, with no commentary and no hint of which ones
   you expect to be wrong, and this brief: check each claim against the code and the platform (a
   finding can be mistaken), accept or reject each one with a reason, and implement only the
   accepted ones. It leaves its changes uncommitted, does not launch the GUI, and finishes with a
   build and the change's targeted tests passing. Its report gives one line per finding:
   ACCEPTED or REJECTED, the reason, and the files changed.
2. **The author agent judges the decisions.** Read every decision against the code, including the
   accepted ones, and form a view on each rejection: agree, or disagree and why. Tell the user,
   **before opening the PR**, which rejections you disagree with. A disagreement goes back to the
   user; the author agent does not overrule the implementer by quietly fixing it. Loose ends the
   implementer found but left alone (a stale cross-reference, say) go to the user too, in the same
   decision list, each marked author-raised. The author agent fixes none of them without the user's
   accept.
3. **The author agent tests the result** (§ 3).

## 3. Test the fixes

Whoever implemented them, the author agent tests the fixed branch before it is committed:

- Review the fix diff line by line.
- Run the full suite.
- Re-run the live checks the original change was verified with, in the debug build (`app-control`;
  `live-ui-testing` for screen-only defects), and compare against the numbers measured before the
  fixes.
- Verify on screen, not by reasoning, any accepted finding that changes drawing, compositing or
  behaviour.

Then commit, with the review fixes in their own commit.

## 4. The PR description's Code quality review section

- That the review was run on this branch by a fresh agent, not the author agent.
- Every finding it returned, each with its decision: accepted and fixed (what changed), or rejected
  and why.
- On the delegated route: that the decisions were delegated, each decision as the implementer gave
  it, and any the author agent disagreed with and what the user did about it.
