use v6.d;

use Graph;
use Graph::Formatish;
use LLM::Functions;
use Hash::Merge;

role LLM::Graph::Formatish does  Graph::Formatish {
    method dot(
            Bool :$svg = False,
            :format(:$output-format) is copy = Whatever,
            Str:D :$engine = 'dot',
            :node-shape(:$node-shapes) is copy = Whatever,
            *%args) {

        # No graph
        if self.graph !~~ Graph:D {
            note 'No graph.';
            return '';
        }

        # Process node shapes
        my %default-node-shapes = Routine => 'ellipse', :RoutineWrapper,
                                  'LLM::Function' => 'ellipse', Str => 'egg',
                                  Callable => 'box', Input => 'parallelogram';
        if $node-shapes.isa(Whatever) { $node-shapes = %() }
        die 'The values of node-shapes is expected to be a hashmap or Whatever.'
        unless $node-shapes ~~ Map:D;

        $node-shapes = merge-hash(%default-node-shapes, $node-shapes, :!positional-append);

        # Delegate to Graph.dot
        my %args2 = %args.grep({ $_.key ∉ <weights node-shape icons > });

        my $res = self.graph.dot(:weights, output-format => 'dot', node-shape => $node-shapes<Callable>, |%args2);

        # LLM-functions over strings
        my @funcs = self.rules.grep({ ($_.value<spec-type> ~~ Str) })».key;

        for @funcs -> $p {
            $res .= subst('"' ~ $p ~ '";', '"' ~ $p ~ '" [shape=' ~ $node-shapes<Str> ~ '];' ~ "\n")
        }

        # LLM functors
        @funcs = self.rules.grep({ $_.value<spec-type> ~~ LLM::Function })».key;

        for @funcs -> $p {
                $res .= subst('"' ~ $p ~ '";', '"' ~ $p ~ '" [shape=' ~ $node-shapes<LLM::Function> ~'];' ~ "\n")
        }

        # Wrapped eval-functions (invoking LLMs in their wrappers)
        my @proc = self.rules.grep({ ($_.value<spec-type> ~~ Routine) && ($_.value<wrapper>:exists) })».key;

        for @proc -> $p {
                $res .= subst('"' ~ $p ~ '";', '"' ~ $p ~ '" [shape=' ~ $node-shapes<Routine> ~ '];' ~ "\n");
                if $node-shapes<RoutineWrapper> {
                        $res .= subst(/ '}' $/, "\nsubgraph { $p }_Cluster \{ cluster=true; style=dashed; color={ %args<node-color> // 'Grey' }\"$p\";\}\n}")
                }
        }

        # Input nodes
        my @inp = (self.graph.vertex-list (-) self.rules.keys).keys;

        for @inp -> $p {
            $res .= subst('"' ~ $p ~ '";', '"' ~ $p ~ '" [shape=' ~ $node-shapes<Input> ~ '];' ~ "\n", :g)
        }

        # Adjust
        $res = $res
                .subst('[weight=2, label=2]', '[weight=2, style=dashed]', :g)
                .subst('[weight=1, label=1]', '[weight=1]', :g)
                .subst('[weight=3, label=3]', '[weight=1]', :g);

        # Output format
        if $svg { $output-format = 'svg' }
        if $output-format.isa(Whatever) { $output-format = 'dot' }

        # Result
        return $output-format eq 'dot' ?? $res !! self!dot-svg($res, :$engine, format => $output-format);
    }
}