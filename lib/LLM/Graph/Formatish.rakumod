use v6.d;

use Graph;
use Graph::Formatish;

role LLM::Graph::Formatish does  Graph::Formatish {
    method dot(
            Bool :$svg = False,
            :format(:$output-format) is copy = Whatever,
            Str:D :$engine = 'dot',
            *%args) {

        if self.graph !~~ Graph:D {
            note 'No graph.';
            return '';
        }

        my %args2 = %args.grep({ $_.key ∉ <weights node-shape> });

        my $res = self.graph.dot(:weights, output-format => 'dot', node-shape => 'ellipse', |%args2);

        # LLM-functions of any type
        my @funcs = self.rules.grep({ ($_.value<llm-function>:exists) })».key;

        for @funcs -> $p {
            $res .= subst('"' ~ $p ~ '";', '"' ~ $p ~ '" [shape=egg];' ~ "\n")
        }

        # Wrapped eval-functions (most likely invoking LLMs in their wrappers)
        my @proc = self.rules.grep({ ($_.value<eval-function>:exists) && ($_.value<wrapper>:!exists) })».key;

        for @proc -> $p {
            $res .= subst('"' ~ $p ~ '";', '"' ~ $p ~ '" [shape=box];' ~ "\n")
        }

        # Input nodes
        my @inp = (self.graph.vertex-list (-) self.rules.keys).keys;

        for @inp -> $p {
            $res .= subst('"' ~ $p ~ '";', '"' ~ $p ~ '" [shape=parallelogram];' ~ "\n", :g)
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