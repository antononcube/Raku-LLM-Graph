use v6.d;

use Graph;
use LLM::Functions;
use LLM::Tooling;
use Hash::Merge;

class LLM::Graph {
    has %.rules is required;
    has $.graph = Whatever;
    has $.llm-evaluator is rw = Whatever;

    constant @ALLOWED_KEYS = <eval-function llm-function listable-llm-function input test-function test-function-input>;
    constant %ALLOWED = @ALLOWED_KEYS.map({ $_ => True }).hash;

    #======================================================
    # Creators
    #======================================================
    submethod BUILD(:%!rules = %(),
                    :$!graph = Whatever,
                    :$!llm-evaluator = Whatever) {
        if $!llm-evaluator.isa(Whatever) {
            $!llm-evaluator = llm-evaluator(llm-configuration(Whatever));
        }
    }

    multi method new(Hash $rules) {
        self.bless(:$rules, graph => Whatever);
    }

    multi method new(%rules, :$llm-evaluator = Whatever) {
        self.bless(:%rules, graph => Whatever, :$llm-evaluator);
    }

    multi method new(:%rules!, :$llm-evaluator = Whatever) {
        self.bless(:%rules, graph => Whatever, :$llm-evaluator);
    }

    #======================================================
    # Clone
    #======================================================
    method clone() {
        LLM::Graph.new(
                rules => %!rules.clone,
                graph => $!graph.defined ?? $!graph.clone !! Whatever,
                llm-evaluator => $!llm-evaluator.defined ?? $!llm-evaluator.clone !! Whatever)
    }

    #======================================================
    # Representation
    #======================================================
    multi method gist(::?CLASS:D:-->Str) {
        return "LLM::Graph(size => {self.rules.elems}, nodes => {self.rules.keys.sort.join(', ')})";
    }

    method Str(){
        return self.gist();
    }

    #======================================================
    # Management methods
    #======================================================
    method drop-results() {
        %!rules .= map({ if $_.value ~~ Map:D { $_.value<result>:delete }; $_ });
        self;
    }

    #======================================================
    # Validators
    #======================================================

    method rule-errors() {
        my @errors;
        for %!rules.kv -> $name, $val {
            if $val ~~ Str:D || $val ~~ (Array:D | List:D | Seq:D) && $val.all ~~ Str:D {
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
                            "Rule '$name' has invalid spec -- " ~
                            'each node must be defined with only one of "eval-function", "llm-function", or "listable-llm-function".')
                }
                if ($val<test-function>:exists) && $val<test-function> !~~ Callable:D {
                    @errors.push(
                            "Rule '$name' has invalid spec -- " ~
                            'node\'s test function must be a Callable:D object.')
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
                when Str:D || $_ ~~ (Array:D | List:D | Seq:D) && $_.all ~~ Str:D {
                    %!rules{$k} = %( llm-function => llm-function($_) )
                }

                # &llm-function returns functors by default since "LLM::Functions:ver<0.3.3>"
                when LLM::Function:D {
                    %!rules{$k} = %( llm-function => $_ )
                }

                when Routine:D {
                    my $wrapper = $_.wrap(-> |c {
                        my $res = callsame;
                        llm-synthesize($res, :$!llm-evaluator)
                    });
                    %!rules{$k} = %( eval-function => $_, :$wrapper )
                }

                when Callable:D {
                    die 'Only Routine:D callables are supported. Please use subs or annonymous subs as callable specs.'
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

    method create-graph($pos-arg = '', %named-args = %()) {

        # Make sure we have hashmaps
        self.normalize-nodes;

        # For each node get the input arguments
        my %args = %!rules.map({ $_.key => $_.value<eval-function> // $_.value<llm-function> // $_.value<listable-llm-function> });
        %args .= map({ $_.key => sub-info($_.value)<parameters>.map(*<name>).List });

        # For each node get the test function input arguments (if any)
        my %testArgs = %!rules.grap({ $_.value<test-function> }).map({ $_.key => $_.value<test-function> });
        %testArgs .= map({ $_.key => sub-info($_.value)<parameters>.map(*<name>).List });

        # Add named args
        %args = %args , %named-args , {'$_' => $pos-arg};
        my %allArgs = merge-hash(%args , %testArgs, :!positional-append);

        # Make edges
        my @edges = (%allArgs.keys X %allArgs.keys).map( -> ($k1, $k2) {
                my $v2 = %allArgs{$k2};
                if $k1 ∈ $v2 || $k1 ∈ $v2».subst(/ ^ <[$%@]> /) {
                    my $weight = 2 * +(%testArgs{$k2}:exists) + +(%args{$k2}:exists);
                    %( from => $k1, to => $k2, :$weight )
                }
            });

        # Make graph
        $!graph = Graph.new(@edges):d;

        # Verify
        die 'Cyclic prompt dependencies are not supported.'
        unless $!graph.is-acyclic;

        return $!graph;
    }

    #======================================================
    # Evaluation
    #======================================================

    method eval-node($node, :$pos-arg = '', *%named-args) {

        return $pos-arg if $node eq '$_';

        return %named-args{$node} with %named-args{$node};

        return %!rules{$node}<result> with %!rules{$node}<result>;

        my %inputs;
        if %!rules{$node}<input> {
            %inputs = %!rules{$node}<input>.map({ $_ => %named-args{$_} // self.eval-node($_, :$pos-arg, |%named-args) })
        }

        # Node function info
        my &func = %!rules{$node}<eval-function> // %!rules{$node}<llm-function> // %!rules{$node}<listable-llm-function>;
        my %info = sub-info(&func);
        my @args = |%info<parameters>;

        # Positional and named arguments
        my @posArgs;
        my %namedArgs;
        for @args -> %rec {
            if !%rec<named> { @posArgs[%rec<position>] = %inputs{%rec<name>.subst(/ ^ <[$%@]> /)} }
            if %rec<named> { %namedArgs{%rec<name>} = %inputs{%rec<name>.subst(/ ^ <[$%@]> /)} }
        }

        @posArgs .= map({ $_.defined ?? $_ !! $pos-arg });

        # Passing positional arguments with non-default values is complicated.
        my $result = &func(|@posArgs, |%namedArgs);

        # Register result
        %!rules{$node}<result> = $result;

        return $result;
    }

    method eval($pos-arg = '', *%named-args, :$nodes = Whatever) {

        # Make the graph if not made already
        # Maybe it should be always created.
        if $!graph.isa(Whatever) { self.create-graph($pos-arg, %named-args) }

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
            %!rules{$k} = [|%v , input => [], result => Nil].Hash;
            with $gr.adjacency-list{$k} {
                %!rules{$k}<input> = $gr.adjacency-list{$k}.keys.Array;
            }
        }

        # For each result node recursively evaluate its inputs
        for @resNodes -> $node {
            # Make sure each evaluated node has the result in its hashmap
            self.eval-node($node, :$pos-arg, |%named-args)
        }

        # Unwrap wrapped subs
        # %!rules .= map({ if $_.value<wrapper> { $_.value<eval-function>.unwrap($_.value<wrapper>) }; $_ });

        return self;
    }
}