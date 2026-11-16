

## Agent skill creation

```text
Are you familiar with the SKILL skills specification of https://agentskills.io ?
```

> Yes. Agent Skills defines reusable capability packages centered on a `SKILL.md` file with YAML metadata and Markdown instructions, optionally accompanied by scripts, references, templates, and assets. I can create, review, or adapt skills that follow the specification.

```text
In the directory "./resources/raku-llm-graph-making" create the "SKILL.md" file, and 
"scripts" and "reference" directories that help with the creation of LLM-graphs with the Raku package "LLM::Graph". 
Analyze the scripts in "./examples". 
Include the abilities to plot graphs.
```

> I’m using the skill-creator skill because this request is specifically to build an Agent Skills package. I’ll inspect the repository examples and linked notebook, then create SKILL.md, scripts/, and reference/ with graph-construction and plotting guidance.
> [...]

---

## Loop

```text
Examine the examples in the file "./docs/LLM-graphs-with-loops.md" and propose an implementation plan for cyclic LLM graphs. 
Do not implement yet.
```

## _Answer_

The examples imply a bounded, stateful feedback model—not simply allowing recursive evaluation. The current implementation explicitly rejects cycles in [`lib/LLM/Graph.rakumod`](/home/vscode/Raku-LLM-Graph/lib/LLM/Graph.rakumod:264), and its recursive memoized evaluator would otherwise recurse indefinitely.

### Proposed semantics

Extend node maps with these loop-control keys:

- `initial-value` — callable that produces the loop anchor’s initial state once per `eval`.
- `max-iterations` — required positive integer safety bound.
- `termination-function` — optional callable evaluated after each completed iteration; a true result stops the loop.

An anchor is the one node in a cyclic component that defines `initial-value`. An iteration means one update of that anchor:

1. Evaluate upstream acyclic inputs once.
2. Seed the anchor with `initial-value`.
3. Evaluate cyclic dependents using the current anchor state.
4. Re-evaluate the anchor using its prior state plus those new dependent results.
5. Run `termination-function`; otherwise repeat until `max-iterations`.
6. Continue evaluating downstream acyclic nodes using the final cycle results.

Thus the actor–critic example becomes: seed `refine` from `draft`; evaluate `critique`; update `refine`; test approval; repeat.

### Implementation plan

1. **Formalize and validate the node-spec API**
   - Add the three control keys to allowed node-spec keys.
   - Validate callable controls and `max-iterations > 0`.
   - Preserve self-dependencies during graph construction; the current edge builder explicitly excludes them, which prevents representing the one-node examples.
   - Replace blanket cycle rejection with structural validation:
     - every cyclic component needs exactly one anchor;
     - anchors require a maximum iteration bound;
     - initially support components that become acyclic when their anchor is treated as prior-iteration state;
     - reject ambiguous multi-feedback structures with a precise diagnostic.

2. **Build a component-level execution plan**
   - Keep the existing dependency graph and plotting model.
   - Classify nodes into acyclic components and cyclic strongly connected components.
   - For each valid cycle, record its anchor, internal evaluation order, upstream dependencies, and downstream consumers.
   - Use a small local SCC implementation if the `Graph` dependency does not expose an appropriate stable API.

3. **Introduce a dedicated iterative evaluator**
   - Retain current `eval-node` recursion for acyclic work.
   - Add an `eval-cycle` path that owns mutable per-run state and never recursively follows an in-cycle edge.
   - Resolve Promises at each dependency boundary; allow independent non-feedback nodes in an iteration to run concurrently.
   - Store final results in existing node `<result>` fields, so downstream nodes and callers retain the current interface.
   - Clear cycle state at the start of every `eval`, just as results are reset today.

4. **Define stop and result behavior precisely**
   - Count completed anchor updates, so `max-iterations => 3` permits three refinements after initialization.
   - Invoke termination after each completed iteration, with the latest values available to its declared parameters.
   - Record lightweight run metadata such as iteration count and stop reason (`termination-function` or `max-iterations`) for inspection and debugging.
   - Decide and document whether explicit `eval` inputs may override an anchor; my recommendation is that an explicit anchor value acts as the initial state and takes precedence over `initial-value`.

5. **Maintain visual and API compatibility**
   - Keep `dot` rendering the actual dependency cycle, including self-loops.
   - Optionally distinguish anchor nodes in DOT output later; this is useful but need not block the evaluator.
   - Preserve existing acyclic behavior, synchronous/asynchronous modes, test functions, and listable LLM nodes.

6. **Test before enabling documentation examples**
   - Deterministic, non-LLM tests for:
     - self-loop limited by `max-iterations`;
     - early termination;
     - actor–critic sequencing;
     - upstream initialization and downstream consumption;
     - sync and async execution;
     - invalid/missing anchors, invalid bounds, and unsupported multi-feedback cycles;
     - repeated `eval` calls without stale state.
   - Add a Promise-failure test so a rejected loop iteration is surfaced rather than silently cached.

7. **Update the loop documentation after implementation**
   - Turn the three examples into executable tests/examples.
   - Correct current draft issues: `evalution-function` should be `eval-function`; `Initial-value` should be lowercase; `$rety` should be `$retry`; and `$critque` should be `$critique`.
   - State the iteration-count semantics and the initial supported cycle shape.

This delivers the examples’ intended self-refinement and actor–critic workflows while keeping cycle behavior deterministic, bounded, and compatible with the existing DAG evaluator.

----

```text
Yes, an explicit anchor value acts as the initial state and takes precedence over initial-value.
The class `Graph` of the package "Graph" has the method `connected-components` for finding strongly connected components.
Proceed with the implementation.
```