use v6.d;

use Graph;
use LLM::Functions;
use LLM::Tooling;

class LLM::Graph {
    has %!rules;
    has $.graph;

    constant @ALLOWED_KEYS = <eval-function llm-function listable-llm-function input test-function test-function-input>;
    constant %ALLOWED = @ALLOWED_KEYS.map({ $_ => True }).hash;

    #======================================================
    # Creators
    #======================================================
    submethod BUILD(:%!rules = %(),
                    :$!graph = Whatever) {
    }

    multi method new(Hash $rules) {
        self.bless(:$rules, graph => Whatever);
    }

    multi method new(:%rules = {}, :$graph = Whatever) {
        self.bless(:%rules, :$graph);
    }

    #======================================================
    # Validators
    #======================================================

    method rule-errors() {
        my @errors;
        for %!rules.kv -> $name, $val {
            if $val ~~ Str:D {
                next;
            }
            elsif $val ~~ Callable:D {
                next;
            }
            elsif $val ~~ Map:D {
                my @bad = $val.keys.grep({ not %ALLOWED{$_} });
                if @bad.elems {
                    @errors.push("Rule '$name' has invalid keys: " ~ @bad.join(', ') ~ '.');
                }
                if ($val.keys (&) <eval-function llm-function listable-llm-function>).elems != 1 {
                    @errors.push(
                            "Rule '$name' has invalid spec --" ~
                            'each node must be defined with only one of "eval-function", "llm-function", or "listable-llm-function".')
                }
            }
            else {
                @errors.push("Rule '$name' has invalid type: " ~ $val.^name ~ '.');
            }
        }
        return @errors;
    }

    method rules-valid(-->Bool) {
        self.rule-errors().elems == 0;
    }

    #======================================================
    # Normalize nodes
    #======================================================

    method normalize-nodes() {
        for %!rules.kv -> $k, $node {
            given $node {
                when Str:D {
                    %!rules{$k} = %( llm-function => llm-function($_) )
                }

                when Callable:D {
                    %!rules{$k} = %( eval-function => $_ )
                }

                when Map:D {
                    #%!rules{$k} = $_
                }
            }
        }
        return %!rules;
    }

    #======================================================
    # Graph creation
    #======================================================

    method create-graph() {

        # Make sure we have hashmaps
        self.normalize-nodes;

        # For each node get the input arguments
        my %args = %!rules.map({ $_.key => $_.value<eval-function> // $_.value<llm-function> // $_.value<listable-llm-function> });
        %args .= map({ $_.key => sub-info($_.value)<parameters>.map(*<name>).List });

        # Make edges
        my @edges = (%args.keys X %args.keys).map( -> ($k1, $k2) {
                my $v2 = %args{$k2};
                if $k1 ∈ $v2 || $k1 ∈ $v2».subst(/ ^ '$'/) {
                    %( from => $k1, to => $k2 )
                }
            });

        note (:@edges);
        # Make graph
        $!graph = Graph.new(@edges):d;

        return $!graph;
    }
}