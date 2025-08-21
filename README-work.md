# LLM::Graph

Raku package used to efficiently schedule and combine multiple LLM generation steps.

The package provides the class `LLM::Graph` with which computations are orchestrated.

-----

## Installation

Package installations from both sources use [zef installer](https://github.com/ugexe/zef)
(which should be bundled with the "standard" Rakudo installation file.)

To install the package from [Zef ecosystem](https://raku.land/) use the shell command:

```
zef install LLM::Graph
```

To install the package from the GitHub repository use the shell command:

```
zef install https://github.com/antononcube/Raku-LLM-Graph.git
```

-----

## Design

Creation of an `LLM::Graph` object in which "node_i" evaluates `fun_i` with results from parent nodes:

```
LLM::Graph.new({name-1 => fun_1, ...})
```

`LLM::Graph` objects are callables. Getting the result of a graph on `input`:

```
LLM::Graph.new(...)(input)
```

### Details and options

- An `LLM::Graph` enables efficient scheduling and integration of multiple LLM generation steps, optimizing evaluation by managing the concurrency of LLM requests.

- Using `LLM::Graph` requires (LLM) service authentication and internet connectivity.
  - Authentication and internet are required if all graph nodes are non-LLM computation specs.
  
- Possible values of the node function spec `fun_i` are:

|                         |                                                      |
|-------------------------|------------------------------------------------------|
| `llm-function(...)`     | an `llm-function` for LLM submission                 |
| `sub (...) {...}`       | a sub for Raku computation submission                |
| `%(key_i => val_i ...)` | a `Map` with detailed node specifications `nodespec` |

* Possible node specifications keys in `nodespec` are:

|                         |                                                   |
|-------------------------|---------------------------------------------------|
| "eval-function"         | arbitrary Raku sub                                |
| "llm-function"          | LLM evaluation via an `llm-function`              |
| "listable-llm-function" | threaded LLM evaluation on list input values      |
| "input"                 | explicit list of nodes required as sub arguments  |
| "test-function"         | whether the node should run                       |
| "test-function-input"   | explicit list of nodes required as test arguments |


- Each node must be defined with only one of "eval-function", "llm-function", or "listable-llm-function".

- The "test-function" specification makes a node evaluation conditional on the results from other nodes.

- Possible "llm-function" specifications `prompt_i` include:

|                                     |                           |
|-------------------------------------|---------------------------|
| "text"                              | static text               |
| ["text1", ...]                      | a list of strings         |
| llm-prompt("name")                  | a repository prompt       |
| `sub ($arg1..) {"Some $arg1 text"}` | templated text            |
| `llm-function(...)`                 | an `LLM::Function` object |


- Any "node_i" result can be provided in input as a named argument. 
  `input` can have one positional argument and multiple named arguments.

- `LLM::Graph` objects have the attribute `llm-evaluator` that is used as a default (or fallback)
  LLM evaluator object.

-----

## Usage examples

### Three poets

Make an LLM graph with three different poets, and a judge that selects the best of the poet-generated poems:

```raku
use LLM::Graph;
use Graph;

my %rules =
        poet1 => "Write a short poem about summer.",
        poet2 => "Write a haiku about winter.",
        poet3 => sub ($topic, $style) {
            "Write a poem about $topic in the $style style."
        },
        judge => sub ($poet1, $poet2, $poet3) {
            [
                "Choose the composition you think is best among these:\n\n",
                "1) Poem1: $poet1",
                "2) Poem2: $poet2",
                "3) Poem3: $poet3",
                "and copy it:"
            ].join("\n\n")
        };

my $gBestPoem = LLM::Graph.new(%rules);
```

Full calculation:

```raku
$gBestPoem.eval(topic => 'hockey', style => 'limerick');
```

Computations dependency graph:

```raku, eval=FALSE
$gBestPoem.dot(engine => 'dot', node-shape => 'ellipse', node-width => 1.2 ):svg
```

![](./docs/Three-poets-graph.svg)


The result by the terminal node("judge"):

```raku
say $gBestPoem.rules<judge>;
```

-----

## TODO

- [ ] TODO Implementation
  - [X] DONE Initial _useful_ version
    - Just using `LLM::Graph`.
  - [X] DONE Conditional evaluation per node
    - Using a test function
  - [ ] TODO Front-end simple sub(s)
    - Like `llm-graph`.
  - [X] DONE Special DOT representation
  - [ ] TODO CLI interface that takes Raku or JSON specs of LLM-graphs
- [ ] TODO Testing
  - [X] DONE LLM-graph initialization
  - [ ] TODO Simple evaluations
- [ ] TODO Documentation
  - [X] DONE Useful README
  - [ ] TODO Three poets notebook.
  - [ ] TODO Comprehensive text summary notebook.

-----

## References

### Blog posts

[AA1] Anton Antonov,
["Parameterized Literate Programming"](https://rakuforprediction.wordpress.com/2025/06/21/parameterized-literate-programming/),
(2025),
[RakuForPrediction at WordPress](https://rakuforprediction.wordpress.com).

### Functions, packages

[AAp1] Anton Antonov, 
[LLM::Functions Raku package](https://github.com/antononcube/Raku-LLM-Functions),
(2023-2025),
[GitHub/antononcube](https://github.com/antononcube).

[AAp2] Anton Antonov, 
[LLM::Prompts Raku package](https://github.com/antononcube/Raku-LLM-Prompts),
(2023-2025),
[GitHub/antononcube](https://github.com/antononcube).

[AAp3] Anton Antonov, 
[Graph Raku package](https://github.com/antononcube/Raku-LLM-Graph),
(2024-2025),
[GitHub/antononcube](https://github.com/antononcube).

[WRIf1] Wolfram Research (2025), 
[LLMGraph](https://reference.wolfram.com/language/ref/LLMGraph.html), 
[Wolfram Language function](https://reference.wolfram.com/language).

### Notebooks

[AAn1] Anton Antonov,
["LLM comprehensive summary template for large texts"](https://community.wolfram.com/groups/-/m/t/3448842),
(2025),
[Wolfram Community](https://community.wolfram.com).

### Videos

[WRIv1] Wolfram Research, Inc.,
["Live CEOing Ep 886: Design Review of LLMGraph](https://www.youtube.com/watch?v=ewU83vHwN8Y),
(2025),
[YouTube/WolframResearch](https://www.youtube.com/@WolframResearch).