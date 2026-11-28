---
name: pre-pr-review
description: The procedure every PR goes through before it opens, and its one CodeRabbit round after. A fresh reviewer agent reviews the whole branch; the user decides which findings to fix, or delegates that to a second fresh implementer agent whose decisions and fixes the author agent then judges and tests; the PR description records every finding; then CodeRabbit's comments go through the same decide-and-test loop with a new implementer agent, and every thread is answered and resolved; then, only when the user asks to land or merge the PR, the author agent merges it. Use before opening any PR, after opening one, when asked to "land the plane", or when the user says to have a fresh agent review, triage or implement review findings.
---

# Pre-PR Review

Every PR is preceded by a code-quality review of the whole branch, and a PR whose description lacks
the **Code quality review** section below is not ready to open. Once it is open, CodeRabbit's review
goes through the same loop once (§ 5), and then, if the user asks to land it, the author agent merges it
(§ 6). The review's lens is the
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
   **before the fixes leave the machine** (before the PR opens, or before the push in § 5), which
   rejections you disagree with. A disagreement goes back to the
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
- Verify on screen, not by reasoning, any accepted finding that changes visible drawing, compositing
  or visible behaviour. A finding that changes only headless behaviour has no visible effect for a
  screen check to show: the author agent instead runs the non-screen check that exercises it (the
  targeted test, or a CLI run through `cli`), and names it in the PR.

Then commit, with the review fixes in their own commit.

## 4. The PR description's Code quality review section

- That the review was run on this branch by a fresh agent, not the author agent.
- Every finding it returned, each with its decision: accepted and fixed (what changed), or rejected
  and why.
- On the delegated route: that the decisions were delegated, each decision as the implementer gave
  it, and any the author agent disagreed with and what the user did about it.

## 5. CodeRabbit's review, after the PR opens

CodeRabbit reviews every PR once it opens and again on each push. Its comments are findings like
the reviewer's, and `CONTRIBUTING.md` § *Comment Resolution* requires every one answered before the
PR merges. They go through the same loop, **once**: the round covers the pass on the PR as opened,
and the fixes it produces are tested by the author agent (§ 3), not by another CodeRabbit pass.
Re-reviewing each fix push never ends, because every pass finds something new in the wording it
just asked for.

1. **Wait for the review.** Poll `gh pr checks <N>` until the `CodeRabbit` check leaves `pending`.
   `Review completed` means it is in. `Review rate limited` means nothing was reviewed: wait and
   comment `@coderabbitai review` to ask again, rather than treating silence as approval. Wait with
   a long interval (minutes), not a tight loop.
2. **Collect every comment, verbatim, across all pages.** Both REST endpoints return 30 items per
   page by default, so every `gh api` call here takes `--paginate`. The inline comments are
   `gh api --paginate repos/<owner>/<repo>/pulls/<N>/comments`, author `coderabbitai[bot]`. The
   nitpicks and "outside diff range" comments CodeRabbit puts in its review body are
   `gh api --paginate repos/<owner>/<repo>/pulls/<N>/reviews`. The REST comments carry no resolved
   state, so take the unresolved threads from GraphQL, `reviewThreads` with `isResolved == false`,
   paginated with `gh api graphql --paginate` and an `$endCursor` variable. Skip its walkthrough
   summary, which asks for nothing.
3. **Decide** (§ 2), the same route the user chose for the pre-PR review unless they say otherwise.
   On the delegated route the implementer is a **new** fresh agent, not the one that handled the
   pre-PR findings: it gets CodeRabbit's comments verbatim with the § 2 brief, and the author agent
   judges its decisions the same way.
4. **Test** (§ 3), then commit the fixes in their own commit and push. If every comment was
   rejected there is nothing to commit or push; make no empty commit.
5. **Answer every thread.** Reply to each CodeRabbit comment with its decision: fixed in `<sha>`
   with what changed, or not changed and why, with the evidence. Then resolve the thread. A
   rejection the author agent disagreed with says so in the reply.
6. **Record it in the PR description:** a **CodeRabbit review** section after *Code quality review*,
   listing every comment with its decision, in the § 4 format.

That ends the round. The push in step 4 makes CodeRabbit review again; do not wait for that pass
or act on it.

## 6. Merge

The author agent merges the PR only when the user has asked to land or merge it (for example, "land
the plane"). A request to open a PR does not ask for a merge: when that is all the user asked, stop
once the PR is ready, report that state, and wait for the user's merge request. Once the user has
asked, the author agent merges the PR itself once all of these hold.

- The CodeRabbit round (§ 5) is done, and every thread it raised, and any human's, is answered
  and resolved.
- `gh pr checks <N>` shows no failing or pending check.
- The PR description has its *Code quality review* and *CodeRabbit review* sections, and the How to
  test comment is posted.
- `gh pr view <N> --json mergeable,mergeStateStatus` reports it mergeable. If `main` moved and the
  branch conflicts, merge `origin/main` in, re-run § 3's suite, and push.

Merge with a merge commit, as the repo's history does: `gh pr merge <N> --merge`. Leave the branch in
place; deleting remote branches is the user's call. Report the merge commit. A human review that
asks for changes, or an unresolved disagreement with the user, stops the merge until the user says.
