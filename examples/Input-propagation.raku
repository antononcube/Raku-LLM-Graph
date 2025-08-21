#!/usr/bin/env raku
use v6.d;

use LLM::Graph;
use LLM::Prompts;
use Graph;

# Non using LLM
#`[
my %rules =
        process-input => { eval-function => { $_ xx 3 } },
        doc => { eval-function => -> $process-input { ($process-input xx 2).join("\n") } },
        ;
]

# Using LLM
my %rules =
        process-input => sub {"Determine the input type of\n\n$_.\n\nThe result should be one of: 'Text', 'URL', 'FilePath', or 'Other'."},
        doc => { eval-function => -> $process-input { ($process-input xx 2).join("\n") } },
        ;

# Create an LLM::Graph object
my $gDoc = LLM::Graph.new(%rules);

# The LLM::Graph object is an is a callable, returns itself
$gDoc('my');

# Show the result
say $gDoc.rules<doc>;

say '-' x 100;

# Show the rules
.say for |$gDoc.rules;