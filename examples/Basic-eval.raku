#!/usr/bin/env raku
use v6.d;

use LLM::Graph;
use LLM::Functions;

# Create LLM-graph
my %rules =
        poet1 => "write a short poem about summer",
        poet2 => "write a haiku about winter",
        judge => sub (Str:D $poet1, Str:D $poet2) {"Choose the best composition of your among these:\n\n1) Poem1: $poet1\n\n2) Poem2: $poet2\n\nand copy it:"}
        ;
#

my $g = LLM::Graph.new(%rules);

# Queries over the LLM-graph object
say '$g.rules-valid' => $g.rules-valid;
say '$g.normalize-nodes' => $g.normalize-nodes;

say '$g.rules' => $g.rules;

$g.create-graph;

say $g.graph;

say '-' x 100;

my $gr = $g.graph.reverse;

say $gr.adjacency-list;
say $gr.adjacency-list<judge>;
say $gr.adjacency-list<poet1>;

say '-' x 100;

# Poet 1
my $poet1 = q:to/END/;
Golden rays through skies so blue,
Whispers warm in morning dew.
Laughter dances on the breeze,
Summer sings through rustling trees.

Fields of green and oceans wide,
Endless days where dreams abide.
Sunset paints the world anew,
Summer’s heart in every hue.
END

# Poet 2
my $poet2 = q:to/END/;
Silent snowflakes fall,
Blanketing the earth in white,
Winter’s breath is still.
END

# Evaluate as a callable or by the method eval,
# by specifying the results of the nodes 'poet1' and 'poet2'
#say $g(:$poet1, :$poet2);
say $g.eval(:$poet1, :$poet2);

# Evaluation without arguments
#say $g.eval;

# Show the result of the terminal node
say $g.rules<judge><result>;

