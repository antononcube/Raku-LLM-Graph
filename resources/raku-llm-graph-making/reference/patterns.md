# LLM graph composition patterns

These patterns are distilled from `examples/*.raku` and `docs/Summarize-large-text.ipynb` in the `LLM::Graph` repository.

## Fan-out, then synthesis

Create several independent LLM nodes and a final node whose signature names all of them. With `:async`, independent branches can be submitted concurrently.

```raku
my %rules =
    Summary => sub ($Text) { "Summarize:\n\n$Text" },
    Topics => sub ($Text) { "List the main topics:\n\n$Text" },
    Critique => sub ($Text) { "Critique:\n\n$Text" },
    Report => {
        eval-function => sub ($Summary, $Topics, $Critique) {
            "# Report\n\n## Summary\n$Summary\n\n## Topics\n$Topics\n\n## Critique\n$Critique"
        }
    };
```

Use `eval-function` for `Report` when assembly itself needs no LLM generation.

## Large-text summarization pipeline

The notebook uses this shape:

```text
raw input -> input classification -> ingestion
                                  |-> title
                                  |-> summary
                                  |-> topics table
                                  |-> thinking-hats feedback
                                  `-> mind map
all derived artifacts ----------------> report -> optional export
```

Implementation decisions that matter:

- Classify `$_` as text, URL, or file path before ingestion.
- Keep I/O and parsing in `eval-function` nodes.
- Fan out independent analysis prompts from the ingested text.
- Assemble Markdown/HTML in one deterministic `Report` node.
- Make export conditional and terminal so ordinary evaluation has no unwanted file side effect.
- Allow expensive nodes, including the title, to be preassigned through `.eval({...})` for partial evaluation and testing.
- Strip fenced JSON or HTML markers before parsing or embedding model output.
- Ask for structured output explicitly and validate it before downstream conversion.

Do not copy the notebook's `shell "open ..."` behavior into automation unless the user explicitly wants the generated file opened.

## Input propagation and overrides

External inputs appear as parameters that do not match node names. The positional graph input is `$_`.

```raku
TypeOfInput => sub ($_) { ... },
IngestText => {
    eval-function => sub ($TypeOfInput, $_) { ... }
},
Title => {
    eval-function => sub ($IngestText, $with-title = Whatever) {
        $with-title ~~ Str:D ?? $with-title !! derive-title($IngestText)
    }
}
```

Named values matching node names override those node results. This enables inexpensive topology and downstream tests without invoking upstream LLMs.

## Conditional branches

Attach `test-function` to the node being gated. Its dependencies are separate from computation dependencies:

```raku
RussianPoem => {
    eval-function => sub { llm-synthesize('Write a short poem.') },
    test-function => sub ($with-russian) {
        $with-russian ~~ Bool:D && $with-russian
            || $with-russian.Str.lc eq any(<true yes>)
    }
}
```

Downstream nodes must tolerate a skipped branch's `Nil` result.

## Iterative revision without a cyclic graph

`LLM::Graph` requires an acyclic dependency graph. Model iteration as an external loop around one or more acyclic graphs:

```raku
for ^$max-iterations {
    $revision-graph.clear;
    $revision-graph.eval({ text => $text });
    my $next = $revision-graph.nodes<Finalize><result>;
    last if !$next.defined || $next eq $text;
    $text = $next;
}
```

Set a finite iteration limit and an explicit convergence condition.

## List mapping

Use `listable-llm-function` when one prompt should be independently applied to each element. Use `llm-function` when the whole list belongs in one request. The former returns an ordered list of results; the latter returns one model response.

## Testing strategy

1. Replace LLM-producing nodes with `eval-function` stubs or preassign their results.
2. Validate `node-spec-errors` and call `create-graph`.
3. Inspect edges and render a plot.
4. Test conditional false/true paths and missing optional inputs.
5. Test final assembly with canned structured outputs.
6. Only then run live model calls, ideally evaluating the smallest necessary terminal-node set.

