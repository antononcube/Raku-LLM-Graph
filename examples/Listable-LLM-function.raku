#!/usr/bin/env raku
use v6.d;

use LLM::Graph;
use LLM::Functions;

my $llm-evaluator = llm-configuration('ollama', model => 'gemma4:e4b');

# Define a "listable-llm-function" to thread over its input elements:

my $parallel =
        llm-graph(
                {
                        NameMap => { listable-llm-function => sub ($_) { llm-synthesize({"write $_ in full letter:\n\n"}) } }
                },
                :$llm-evaluator):async;

# Evaluate the graph with LLM generation submitted concurrently:

say (:$parallel);

$parallel.eval(<1 2 3>);

my $text = $parallel.nodes<NameMap><result>;

say (text => $text.raku);

# Compare with the "llm-function" behavior;
# a single LLM generation is submitted with the entire list, returning a single output:

my $sequential =
        llm-graph(
                {
                        NameMap => { llm-function => sub ($_) { llm-synthesize({"write $_ in full letter:\n\n"}) } }
                },
                :$llm-evaluator):async;

say (:$sequential);

$sequential.eval(<1 2 3>);

my $text2 = $sequential.nodes<NameMap><result>;

say (text2 => $text2.raku);

# =========================================================
# Expected output:
#
# parallel => LLM::Graph(size => 1, nodes => NameMap)
# text => $["one", "two", "three"]
#
# sequential => LLM::Graph(size => 1, nodes => NameMap)
# text2 => "one, two, three"