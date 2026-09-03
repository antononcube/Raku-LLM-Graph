# Plotting LLM::Graph graphs

`LLM::Graph` supplies a specialized `.dot` method on top of `Graph::Formatish`. It distinguishes node roles and condition edges instead of producing a generic graph plot.

## Render directly

Build topology first; this does not evaluate LLM nodes:

```raku
$graph.create-graph;

my $dot = $graph.dot(theme => 'default');
spurt 'graph.dot', $dot;

my $svg = $graph.dot(
    :svg,
    engine => 'dot',
    theme => 'ortho',
    node-width => 1.2,
    graph-size => 1.5
);
spurt 'graph.svg', $svg;
```

Equivalent SVG idiom used in the notebooks:

```raku
$graph.dot(node-width => 1.2, theme => 'default'):svg
```

For notebook display, return the SVG string in an HTML/SVG-capable cell. For scripts and reports, write it to a file.

## Themes and formats

- `theme => 'default'` uses the standard layout.
- `theme => 'ortho'` uses orthogonal splines and more angular LLM-node shapes. Synonyms such as `orthogonal` are normalized internally.
- `engine => 'dot'` is the usual Graphviz engine.
- No output format, or `output-format => 'dot'`, returns DOT source.
- `:svg` or `output-format => 'svg'` returns SVG. Other Graphviz-supported formats such as `png` and `pdf` can be requested through `output-format` when the local toolchain supports them.

Graphviz must be available for rendered formats. DOT source generation itself does not require launching a viewer.

## Visual semantics

Default shapes are chosen from normalized node types:

| Element | Typical default shape |
|---|---|
| Static string prompt | egg |
| `LLM::Function` | ellipse |
| Wrapped prompt-template routine | ellipse, optionally outlined by a dashed cluster |
| Ordinary callable/eval node | box |
| External input | parallelogram |

Condition-only dependencies are dashed. Ordinary computation dependencies are solid. Shapes can be overridden with `node-shapes => {...}`; preserve distinctions unless the user requests a uniform style.

## Helper script contract

The included plotting helper expects a trusted Raku file whose final expression returns an `LLM::Graph` object:

```raku
use LLM::Graph;

my %rules =
    A => 'Write a greeting.',
    B => sub ($A) { "Improve this greeting:\n\n$A" };

llm-graph(%rules)
```

Render it from the repository root:

```shell
raku -Ilib resources/raku-llm-graph-making/scripts/plot-llm-graph.raku \
  --output=graph.svg --theme=ortho --inputs=topic,include graph-definition.raku
```

List named external inputs in `--inputs=name1,name2` so they appear as graph vertices. The helper executes the definition file, validates node specs, calls `create-graph`, and writes the plot. It deliberately does not call `.eval`.
