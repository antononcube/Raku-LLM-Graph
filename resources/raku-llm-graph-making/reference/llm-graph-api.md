# LLM::Graph working reference

## Minimal graph

```raku
use LLM::Graph;

my %rules =
    Draft => sub ($topic) { "Write a short draft about $topic." },
    Polish => sub ($Draft) { "Polish this draft:\n\n$Draft" },
    WordCount => {
        eval-function => sub ($Polish) { $Polish.words.elems }
    };

my $graph = llm-graph(%rules, :async, :progress);
$graph.eval({ topic => 'dependency graphs' });
say $graph.nodes<Polish><result>;
say $graph.nodes<WordCount><result>;
```

`Draft` depends on the external input `topic`; `Polish` depends on `Draft`; and `WordCount` depends on `Polish`. Dependencies are inferred from callable parameter names.

## Node forms

| Form | Meaning |
|---|---|
| `Name => "prompt"` | Static LLM prompt |
| `Name => ["part 1", "part 2"]` | Multipart static LLM prompt |
| `Name => sub ($Input) { ... }` | Build a prompt from dependencies, then submit it to the LLM |
| `Name => { eval-function => sub ($Input) { ... } }` | Run ordinary Raku code; do not automatically LLM-submit its result |
| `Name => { llm-function => $function }` | Invoke an explicit `LLM::Function` or compatible callable |
| `Name => { listable-llm-function => sub ($items) { ... } }` | Invoke once per element of exactly one list input and preserve result order |

Detailed specs may additionally contain `test-function`, `input`, and `test-function-input`. The implementation normally infers inputs from signatures; use explicit input fields only when inference cannot express the intended dependency.

Aliases accepted during normalization are `eval-sub`, `llm-sub`, `listable-llm-sub`, and `test-sub`, but prefer canonical keys in new code.

## Dependency inference

- A parameter `$Foo`, `@Foo`, or `%Foo` refers to node or external input `Foo`.
- `$_`, `@_`, and `%_` refer to the positional graph input.
- Parameters of `test-function` also produce edges. Plotting renders condition-only edges as dashed.
- Defaulted parameters allow an input to be optional, for example `sub ($Title, $with-title = Whatever)`.
- Node names are case-sensitive. Prefer identifier-friendly names and match them exactly in signatures.
- `create-graph` rejects cyclic dependencies.

Inspect topology without invoking any node:

```raku
die $graph.node-spec-errors.join("\n") unless $graph.has-valid-node-specs;
$graph.create-graph;
.say for $graph.graph.edges(:dataset);
```

When the topology depends on the names of supplied inputs, pass representative values:

```raku
$graph.create-graph('', { topic => 'sample', with-export => False });
```

## Construction and evaluator configuration

Equivalent constructors:

```raku
my $g1 = LLM::Graph.new(%rules, llm-evaluator => $evaluator, :async, :progress);
my $g2 = llm-graph(%rules, llm-evaluator => $evaluator, :async, :progress);
```

Asynchronous evaluation is the default. Independent prompt branches can therefore run concurrently. Disable it with `:!async` when deterministic synchronous behavior is needed.

Use `llm-configuration(...)` from `LLM::Functions` or `LLM::Tooling` according to the installed package API, then pass the resulting evaluator/configuration as shown by the local examples. Keep credentials out of source files.

## Evaluation and partial evaluation

Evaluate terminal nodes:

```raku
$graph.eval({ topic => 'Raku' });
```

Evaluate only selected nodes:

```raku
$graph.eval({ topic => 'Raku' }, 'Summary');
$graph.eval({ topic => 'Raku' }, <Summary TopicsTable>);
```

Supply the positional input:

```raku
$graph.eval('large text');
# Equivalent explicit form:
$graph.eval({ '$_' => 'large text' });
```

Preassign any node result to skip its computation and allow downstream evaluation:

```raku
$graph.eval({
    '$_' => $text,
    TypeOfInput => 'Text',
    Title => 'A supplied title'
});
```

The graph object is callable, so `$graph(...)` delegates to `.eval(...)`, but prefer `.eval` when clarity matters.

## Conditions, listable nodes, and caching

Conditional node:

```raku
Export => {
    eval-function => sub ($Report) { spurt 'Report.md', $Report },
    test-function => sub ($export = False) {
        $export ~~ Bool:D && $export
    }
}
```

Listable node:

```raku
NameMap => {
    listable-llm-function => sub ($_) {
        llm-synthesize("Write $_ in full letters.")
    }
}
```

A listable function requires exactly one list-valued node input, or a list positional input. Calls are concurrent and output order follows input order.

Results are cached in each node's `result` field. Reset all or selected nodes before recomputation:

```raku
$graph.clear;
$graph.clear('Summary');
$graph.clear(<Summary Report>);
```

Access results with `$graph.nodes<Summary><result>`. A conditionally skipped node records `Nil`.

