#!/usr/bin/env raku
use v6.d;

use MONKEY-SEE-NO-EVAL;
use Graph;
use LLM::Graph;

sub load-graph(Str:D $file --> LLM::Graph:D) {
    my $path = $file.IO.absolute.IO;
    die "Graph definition does not exist: ⎡$path⎦" unless $path.f;

    my $graph = EVALFILE($path.Str);
    die "Expected $path to return an LLM::Graph as its final expression; got ⎡{$graph.^name}⎦.\n"
    unless $graph ~~ LLM::Graph:D;
    $graph
}

sub MAIN(
    Str:D $graph-file,
    Str:D :$inputs = '',
    Bool:D :$show-nodes = True,
    Bool:D :$show-edges = True
) {
    my $graph = load-graph($graph-file);
    my @errors = $graph.node-spec-errors;

    if @errors {
        note "Invalid node specifications:";
        note "  - $_" for @errors;
        exit 2;
    }

    my @input-names = $inputs.split(',').map(*.trim).grep(*.chars);
    my %sample-inputs = @input-names.map({ $_ => '(sample)' }).Hash;
    $graph.create-graph('', %sample-inputs) unless $graph.graph ~~ Graph:D;

    say "Valid LLM::Graph with {$graph.nodes.elems} nodes.";
    say "Nodes: \"{$graph.nodes.keys.sort.join('", "')}\"." if $show-nodes;

    if $show-edges {
        say 'Edges:';
        my @edges = $graph.graph.edges(:dataset).Array;
        if @edges {
            .say for @edges;
        } else {
            say '  (none)';
        }
    }
}
