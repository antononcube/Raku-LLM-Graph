#!/usr/bin/env raku
use v6.d;

use LLM::Graph;
use LLM::Functions;
use Graph;

# Create LLM-graph
my %rules =
        poet1 => "Write a short poem about summer.",
        poet2 => "Write a haiku about winter.",
        poet3 => sub ($topic, $style) {
            "Write a poem about $topic in the $style style."
        },
        poet4 => {
                eval-function => {llm-synthesize('You are a famous Russian poet. Write a short poem about playing bears.')},
                test-function => -> $with-russian { $with-russian ~~ Bool:D && $with-russian || $with-russian.Str.lc ∈ <true yes> }
        },
        judge => sub ($poet1, $poet2, $poet3, $poet4) {
            [
                "Choose the composition you think is best among these:\n\n",
                "1) Poem1: $poet1",
                "2) Poem2: $poet2",
                "3) Poem3: {$poet4.defined && $poet4 ?? $poet4 !! $poet3}",
                "and copy it:"
            ].join("\n\n")
        };

my $gBestPoem = LLM::Graph.new(%rules);

# Show edges dataset
.say for $gBestPoem.create-graph('', {topic => 'hockey', style => 'limerick', with-russian => 'yes', poet1 => 'meh', poet2 => 'blah blah'}).graph.edges(:dataset);

# Queries
say '$gBestPoem.has-valid-node-specs' => $gBestPoem.has-valid-node-specs;
say '$gBestPoem.normalize-nodes:';
.say for |$gBestPoem.normalize-nodes;

say '=' x 100;

# Evaluate by imposing results
$gBestPoem.eval(topic => 'hockey', style => 'limerick', with-russian => 'no', poet1 => 'meh', poet2 => 'blah blah', with-russian => 'yes');

# Show nodes after the evaluation
say 'poet3:';
.say for |$gBestPoem.nodes<poet3>;

say '-' x 100;

say 'poet4:';
.say for |$gBestPoem.nodes<poet4>;

say '-' x 100;

say 'judge:';
.say for |$gBestPoem.nodes<judge>;