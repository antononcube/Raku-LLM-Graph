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

        # Make graph
        $!graph = Graph.new(@edges):d;

        return $!graph;
    }

    #======================================================
    # Evaluation
    #======================================================

    method eval-node($node) {
        with %!rules{$node}<result> {
            return %!rules{$node}<result>;
        }

        my %inputs;
        if %!rules{$node}<input> {
            %inputs = %!rules{$node}<input>.map({ $_ => self.eval-node($_) })
        }

        # Node function info
        my &func = %!rules{$node}<eval-function> // %!rules{$node}<llm-function> // %!rules{$node}<listable-llm-function>;
        my %info = sub-info(&func);
        my @args = %info<parameters>;

        # Positional and named arguments
        my @posArgs;
        my %namedArgs;
        for @args -> %rec {
            if !%rec<named> { @posArgs[%rec<position>] = %inputs{%rec<name>.subst(/ ^ <[$%@]> /)} }
            if %rec<named> { %namedArgs{%rec<name>} = %inputs{%rec<name>.subst(/ ^ <[$%@]> /)} }
        }

        # Passing positional arguments with non-default values is complicated.
        my $result = &func.(|@posArgs, |%namedArgs);

        # Register result
        %!rules<result> = $result;

        return $result;
    }

    method eval($nodes = Whatever) {

        # Make the graph if not made already
        # Maybe it should be always created.
        if $!graph.isa(Whatever) { self.create-graph }

        # Determine result nodes
        my @resNodes = do given $nodes {
            when Whatever {
                $!graph.vertex-out-degree(:p).grep({ $_.value == 0 })».key
            }

            when $_ ~~ Str:D && (%!rules{$_}:exists) {
                [$, ]
            }

            when $_ ~~ (List:D | Array:D | Seq:D) && $_.all ~~ Str:D && ([&&] $_.map(-> $k { %!rules{$k}:exists })) {
                $_
            }

            default {
                note 'The first argument is expected to be a node name, a list of node names, or Whatever.';
                return Nil;
            }
        }

        # Reverse the graph
        my $gr = $!graph.reverse;

        # Expand the hashmap of each node with inputs
        for %!rules.kv -> $k, %v {
            %!rules{$k} = %v , {input => [], result => Nil};
            with $gr.adjacency-list{$k} {
                %!rules{$k}<input> = $gr.adjacency-list{$k}.keys;
            }
        }

        # For each result node recursively evaluate its inputs
        for @resNodes -> $node {
            # Make sure each evaluated node has the result in its hashmap
            self.eval-node($node)
        }

        return self;
    }
}