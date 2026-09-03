---
name: raku-llm-graph-making
description: Design, implement, inspect, and plot LLM computation graphs in Raku with LLM::Graph. Use for graph node specifications, inferred dependencies, conditional or listable nodes, partial evaluation, large-text summarization pipelines, and DOT/SVG graph visualizations.
---

# Make Raku LLM graphs

Build `LLM::Graph` workflows whose node signatures clearly express data dependencies and whose LLM calls, ordinary Raku transformations, conditions, and outputs are easy to inspect.

## Workflow

1. Inspect the repository's installed package version and nearby examples before assuming an API.
2. Translate the requested workflow into named nodes. Use stable Raku identifiers because a parameter such as `$Summary` creates a dependency on the node named `Summary`.
3. Choose the narrowest node form:
   - a `Str` or list of strings for a static LLM prompt;
   - a `sub (...) { ... }` when its returned text should be submitted to the LLM;
   - `{ eval-function => sub (...) { ... } }` for ordinary Raku computation;
   - `{ llm-function => ... }` for an explicit LLM function;
   - `{ listable-llm-function => ... }` for element-wise concurrent LLM evaluation of exactly one list input.
4. Add `test-function` only when execution is genuinely conditional. Its parameter names create condition-only dependencies.
5. Construct with `llm-graph(%rules, ...)` or `LLM::Graph.new(%rules, ...)`, then check `node-spec-errors` before evaluation.
6. Call `create-graph` to inspect or plot without invoking an LLM. Confirm the graph is acyclic and that inferred edges match the intended flow.
7. Evaluate only the needed terminal node(s), passing external inputs or precomputed node results through `.eval`.
8. Read results from `$graph.nodes<NodeName><result>`. Call `.clear` before recomputation when cached results must not be reused.
9. Plot the dependency graph when it helps explain or verify the pipeline.

## Routing

- Read [reference/llm-graph-api.md](reference/llm-graph-api.md) for node forms, dependency inference, evaluation, validation, and caching semantics.
- Read [reference/patterns.md](reference/patterns.md) for composition patterns distilled from the repository examples and the large-text summarization notebook.
- Read [reference/plotting.md](reference/plotting.md) when producing DOT, SVG, PNG, PDF, or explaining the plot's shapes and edges.
- Use `scripts/check-llm-graph.raku` to validate and list inferred edges for a graph-definition file without evaluating its nodes. Pass named external inputs as `--inputs=name1,name2` so their edges are included.
- Use `scripts/plot-llm-graph.raku` to render such a definition file. These helpers execute the supplied Raku file; use them only with trusted local code.

## Important constraints

- Keep the graph acyclic. Implement iterative critique/revision by repeatedly evaluating and clearing an acyclic graph, not by introducing cyclic node dependencies.
- Do not place ordinary deterministic work in a bare `sub`: bare routines are treated as prompt templates and their return values are LLM-submitted. Wrap deterministic work in `eval-function`.
- Each detailed node spec must contain exactly one of `eval-function`, `llm-function`, or `listable-llm-function`.
- Preserve exact parameter/node spelling and case. External inputs become graph vertices too; the positional input is represented by `$_`.
- Avoid LLM calls merely to validate topology or render a plot. `create-graph` and `.dot` are sufficient.
- Do not open rendered files or make network calls unless the user requests it.
