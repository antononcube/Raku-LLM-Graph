use v6.d;

use Graph;

class LLMGraph {
    has %!rules;
    has $.graph;

    constant @ALLOWED_KEYS = <evaluation-function llm-function listable-llm-function input test-function test-function-input>;
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
}