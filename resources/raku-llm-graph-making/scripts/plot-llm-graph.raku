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
    Str:D :$output = 'llm-graph.svg',
    Str:D :$format = 'svg',
    Str:D :$theme = 'default',
    Str:D :$engine = 'dot',
    Str:D :$inputs = '',
    Numeric:D :$node-width = 1.2,
    Numeric:D :$graph-size = 1.5,
    Bool:D :$force = False
) {
    my $destination = $output.IO.absolute.IO;
    die "Output already exists: $destination (pass --force to replace it).\n"
        if $destination.e && !$force;

    my $graph = load-graph($graph-file);
    my @errors = $graph.node-spec-errors;
    die "Invalid node specifications:\n  - {@errors.join("\n  - ")}\n" if @errors;

    my @input-names = $inputs.split(',').map(*.trim).grep(*.chars);
    my %sample-inputs = @input-names.map({ $_ => '(sample)' }).Hash;
    $graph.create-graph('', %sample-inputs) unless $graph.graph ~~ Graph:D;

    my $rendered = $graph.dot(
        :$engine,
        :$theme,
        :$node-width,
        :$graph-size,
        output-format => $format
    );

    die "Plot renderer returned no content. Check the requested format and Graphviz installation.\n"
    unless $rendered.defined && $rendered.chars;

    spurt $destination, $rendered;
    say "Wrote {$format.uc} graph to ⎡$destination⎦.";
}
