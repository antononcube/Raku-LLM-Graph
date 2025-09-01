use v6.d;

use Graph;
use LLM::Functions;
use LLM::Tooling;
use Hash::Merge;
use LLM::Graph::Formatish;

class LLM::Graph
        does Callable
        does LLM::Graph::Formatish {
    has %.nodes is required;
    has $.graph = Whatever;
    has $.llm-evaluator is rw = Whatever;
    has Bool $.async is rw = True;

    constant @ALLOWED_KEYS = <eval-function llm-function listable-llm-function input test-function test-function-input>;
    constant %ALLOWED = @ALLOWED_KEYS.map({ $_ => True }).hash;

    #======================================================
    # Creators
    #======================================================
    submethod BUILD(:%!nodes = %(),
                    :$!graph = Whatever,
                    :$!llm-evaluator = Whatever,
                    Bool:D :$!async = True
                    ) {
        if $!llm-evaluator.isa(Whatever) {
            $!llm-evaluator = llm-evaluator(llm-configuration(Whatever));
        }
    }


    multi method new(%nodes, :e(:$llm-evaluator) = Whatever, Bool:D :a(:$async) = True) {
        self.bless(:%nodes, graph => Whatever, :$llm-evaluator, :$async);
    }

    multi method new(:%nodes!, :e(:$llm-evaluator) = Whatever, Bool:D :a(:$async) = True) {
        self.bless(:%nodes, graph => Whatever, :$llm-evaluator, :$async);
    }

    #======================================================
    # Clone
    #======================================================
    method clone() {
        LLM::Graph.new(
                nodes => %!nodes.clone,
                graph => $!graph.defined ?? $!graph.clone !! Whatever,
                llm-evaluator => $!llm-evaluator.defined ?? $!llm-evaluator.clone !! Whatever,
                :$!async)
    }

    #======================================================
    # Representation
    #======================================================
    multi method gist(::?CLASS:D:-->Str) {
        return "LLM::Graph(size => {self.nodes.elems}, nodes => {self.nodes.keys.sort.join(', ')})";
    }

    method Str(){
        return self.gist();
    }

    #======================================================
    # Management methods
    #======================================================

    # A more universal name would be "result-drop". (But I do not like it.)
    multi method clear() {
        %!nodes.map({
            if $_.value ~~ Map:D {
                $_.value<result>:delete;
                $_.value<input>:delete;
                $_.value<test-function-result>:delete;
                $_.value<test-function-input>:delete;
            };
            $_
        });
        $!graph = Whatever;
        return self;
    }

    multi method clear($node) {
        return $node.isa(Whatever) ?? self.clear !! self.clear([$node,]);
    }

    multi method clear(@nodes) {
        %!nodes
                .grep({ $_.key ∈ @nodes })
                .map({
                    if $_.value ~~ Map:D {
                        $_.value<result>:delete;
                        $_.value<input>:delete;
                        $_.value<test-function-result>:delete;
                        $_.value<test-function-input>:delete;
                    };
                    $_
                });
        $!graph = Whatever;
        return self;
    }

    #======================================================
    # Validators
    #======================================================

    method node-spec-errors() {
        my @errors;
        for %!nodes.kv -> $name, $val {
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

    method has-valid-node-specs(-->Bool) {
        self.node-spec-errors().elems == 0;
    }

    #======================================================
    # Normalize nodes
    #======================================================

    method normalize-nodes() {
        for %!nodes.kv -> $k, $node {
            given $node {
                when ($_ ~~ Str:D || $_ ~~ (Array:D | List:D | Seq:D) && $_.all ~~ Str:D) && self.async {
                    %!nodes{$k} = %( eval-function => { start llm-synthesize($node) }, spec-type => Str )
                }

                when ($_ ~~ Str:D || $_ ~~ (Array:D | List:D | Seq:D) && $_.all ~~ Str:D) && !self.async {
                    %!nodes{$k} = %( llm-function => llm-function($_), spec-type => Str )
                }

                # &llm-function returns functors by default since "LLM::Functions:ver<0.3.3>"
                when $_ ~~ LLM::Function:D && self.async {
                    %!nodes{$k} = %( eval-function => -> **@args, *%args { start $node(|@args, |%args) }, spec-type => LLM::Function )
                }

                when $_ ~~ LLM::Function:D && !self.async {
                    %!nodes{$k} = %( llm-function => $_, spec-type => LLM::Function )
                }

                when $_ ~~ Routine:D && self.async {
                    my $wrapper = $_.wrap(-> |c {
                        my $res = callsame;
                        start llm-synthesize($res, :$!llm-evaluator)
                    });
                    %!nodes{$k} = %( eval-function => $_, :$wrapper, spec-type => Routine )
                }

                when $_ ~~ Routine:D && !self.async {
                    my $wrapper = $_.wrap(-> |c {
                        my $res = callsame;
                        llm-synthesize($res, :$!llm-evaluator)
                    });
                    %!nodes{$k} = %( eval-function => $_, :$wrapper, spec-type => Routine )
                }

                when Callable:D {
                    die 'Only Routine:D callables are supported. Please use subs or annonymous subs as callable specs.'
                }

                when Map:D {
                    my $spec-type = $_<eval-function>:exists ?? Callable !! LLM::Function;
                    %!nodes{$k} = merge-hash($_ , {:$spec-type})
                }
            }
        }
        return self;
    }

    #======================================================
    # Graph creation
    #======================================================

    method create-graph($pos-arg = '', %named-args = %()) {

        # Make sure we have hashmaps
        self.normalize-nodes;

        # For each node get the input arguments
        my %funcArgs = %!nodes.map({ $_.key => $_.value<eval-function> // $_.value<llm-function> // $_.value<listable-llm-function> });
        %funcArgs .= map({ $_.key => sub-info($_.value)<parameters>.map(*<name>).List });

        # For each node get the test function input arguments (if any)
        my %testArgs = %!nodes.grep({ $_.value<test-function> }).map({ $_.key => $_.value<test-function> });
        %testArgs .= map({ $_.key => sub-info($_.value)<parameters>.map(*<name>).List });

        # Add named args
        my %args = %funcArgs.clone , %named-args , {'$_' => $pos-arg // '(Any)'};
        my %allArgs = merge-hash(%args , %testArgs, :positional-append);

        # Make edges
        my @edges = (%allArgs.keys X %allArgs.keys).grep({ $_.head ne $_.tail }).map( -> ($k1, $k2) {
                my $v2 = %allArgs{$k2};
                if $k1 ∈ $v2 || $k1 ∈ $v2».subst(/ ^ <[$%@]> /) {
                    my $weight = 2 * +((%testArgs{$k2}:exists) && ($k1 ∈ %testArgs{$k2} || $k1 ∈ %testArgs{$k2}».subst(/ ^ <[$%@]> /)));
                    $weight += +((%funcArgs{$k2}:exists) && ($k1 ∈ %funcArgs{$k2} || $k1 ∈ %funcArgs{$k2}».subst(/ ^ <[$%@]> /)));
                    %( from => $k1, to => $k2, :$weight )
                }
            });

        # Make graph
        $!graph = Graph.new(@edges):d;

        # Verify
        die 'Cyclic prompt dependencies are not supported.'
        unless $!graph.is-acyclic;

        return self;
    }

    #======================================================
    # Evaluation
    #======================================================

    method eval-func(&func, %inputs, :$pos-arg = '') {

        # Node function info
        my %info = sub-info(&func);
        my @args = |%info<parameters>;

        # Positional and named arguments
        my @posArgs;
        my %namedArgs;
        my %namedSlurpyArgs;
        for @args -> %rec {

            # Positional argument handling
            if !%rec<named> {
                @posArgs[%rec<position>] = do given %rec<name> {
                    when %rec<name> ∈ <$_ @_ %_> {
                        %inputs{%rec<name>} // %rec<default>
                     }
                    default {
                        %inputs{%rec<name>.subst(/ ^ <[$%@]> /)} // %rec<default>
                    }
                }

                if !@posArgs[%rec<position>].defined && !%rec<default>.defined && !%rec<default>.isa(Whatever) {
                    # How many times the pos-arg is going to be used?
                    @posArgs[%rec<position>] = $pos-arg
                }
            }

            # Named argument handling
            if %rec<named> {
                %namedArgs{%rec<name>} = %inputs{%rec<name>.subst(/ ^ <[$%@]> /)} // %rec<default>;
                %namedSlurpyArgs{%rec<name>} = %rec<slurpy>;
            }
        }

        %namedArgs .= map({ %namedSlurpyArgs{$_.key} ?? $_ !! ($_.key.subst(/ ^ <[$%@]> /) => $_.value) });

        # Passing positional arguments with non-default values is complicated.
        my $result = &func(|@posArgs, |%namedArgs);

        return $result;
    }

    method eval-test-node($node, :$pos-arg = '', :%named-args = %()) {

        return $pos-arg if $node eq '$_';

        return %named-args{$node} with %named-args{$node};

        return True without %!nodes{$node}<test-function>;

        return %!nodes{$node}<test-function-result> with %!nodes{$node}<test-function-result>;

        my %inputs;
        if %!nodes{$node}<test-function-input> {
            # Using
            #   %named-args{$_} // self.eval-node($_, :$pos-arg, :%named-args)
            # wont let to be registered the results of nodes that are parents
            # to test functions only.
            %inputs = %!nodes{$node}<test-function-input>.map({ $_ => self.eval-node($_, :$pos-arg, :%named-args) })
        }

        # Node function info
        my &func = %!nodes{$node}<test-function>;
        my $result = self.eval-func(&func, %inputs, :$pos-arg);

        # Register result -- is this needed?
        %!nodes{$node}<test-function-result> = $result;

        return $result;
    }

    method eval-node($node, :$pos-arg = '', :%named-args = %()) {

        return $pos-arg if $node eq '$_';

        # If node name with a given value in the inputs,
        # then register that value as a result and leave.
        if (%!nodes{$node}:exists) && (%named-args{$node}:exists) {
            %!nodes{$node}<result> = %named-args{$node};
            return %named-args{$node};
        }

        return %named-args{$node} with %named-args{$node};

        return %!nodes{$node}<result> with %!nodes{$node}<result>;

        if !self.eval-test-node($node, :$pos-arg, :%named-args) {
            # Register non-result
            %!nodes{$node}<result> = Nil;
            return Nil;
        }

        my %inputs;
        if %!nodes{$node}<input> {
            # Using
            #   %named-args{$_} // self.eval-node($_, :$pos-arg, :%named-args)
            # is elegant but it does not register the node result. (See above.)
            %inputs = %!nodes{$node}<input>.map({ $_ => self.eval-node($_, :$pos-arg, :%named-args) })
        }

        # Select the inputs that are promises
        my @inputPromises = %inputs.grep({ $_.value ~~ Promise:D })».value;

        # Wait for all promises to finish
        if @inputPromises {
            my $allDone = Promise.allof(@inputPromises);
            await($allDone);
            %inputs .= map({ $_.value ~~ Promise:D ?? ($_.key => $_.value.result) !! $_ });
        }

        # Node function info
        my &func = %!nodes{$node}<eval-function> // %!nodes{$node}<llm-function> // %!nodes{$node}<listable-llm-function>;
        my $result = self.eval-func(&func, %inputs, :$pos-arg);

        # Register result
        if self.graph.vertex-out-degree($node) == 0 && $result ~~ Promise:D {
            await($result);
            $result = $result.result;
        }
        %!nodes{$node}<result> = $result;

        return $result;
    }

    sub is-nodes-spec($x) { $x.isa(Whatever) || $x ~~ Str:D || $x ~~ (Array:D | List:D | Seq:D) && $x.all ~~ Str:D }

    multi method eval($arg where $arg !~~ Pair:D, $nodes where is-nodes-spec($nodes) = Whatever) {
        return self.eval({'$_' => $arg}, :$nodes);
    }

    multi method eval(*%named-args) {
        return self.eval(%named-args, nodes => Whatever);
    }

    multi method eval(%named-args!, $nodes where is-nodes-spec($nodes) = Whatever) {
        my $pos-arg = %named-args<$_>;

        # Make the graph if not made already
        # Maybe it should be always created.
        if $!graph.isa(Whatever) { self.create-graph($pos-arg, %named-args) }

        # Determine result nodes
        my @resNodes = do given $nodes {
            when Whatever {
                $!graph.vertex-out-degree(:p).grep({ $_.value == 0 })».key
            }

            when $_ ~~ Str:D && (%!nodes{$_}:exists) {
                [$, ]
            }

            when $_ ~~ (List:D | Array:D | Seq:D) && $_.all ~~ Str:D && ([&&] $_.map(-> $k { %!nodes{$k}:exists })) {
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
        for %!nodes.kv -> $k, %v {
            %!nodes{$k} = [|%v , input => [], test-function-input => [], result => Nil].Hash;
            with $gr.adjacency-list{$k} {
                if %v<test-function>:exists {
                    # See how the dependency graph is made -- test-function input edges have weight 2 or 3
                    %!nodes{$k}<input> = $gr.adjacency-list{$k}.grep({ $_.value == 1 }).Hash.keys.Array;
                    %!nodes{$k}<test-function-input> = $gr.adjacency-list{$k}.grep({ $_.value >= 2 }).Hash.keys.Array;
                } else {
                    %!nodes{$k}<input> = $gr.adjacency-list{$k}.keys.Array;
                }
            }
        }

        # For each result node recursively evaluate its inputs
        for @resNodes -> $node {
            # Make sure each evaluated node has the result in its hashmap
            self.eval-node($node, :$pos-arg, :%named-args)
        }

        # Unwrap wrapped subs
        # %!nodes .= map({ if $_.value<wrapper> { $_.value<eval-function>.unwrap($_.value<wrapper>) }; $_ });

        return self;
    }

    submethod CALL-ME(|c) { c.list.elems == 0 ?? self.eval(c.hash) !! self.eval(|c); }
}

#| Creator of an LLM::Graph object.
#| C<%nodes> -- LLM graph node specs.
#| C<:e(:$llm-evaluator)> -- LLM evaluator spec.
#| C<:a(:$async)> -- Should the evaluations of LLM computation specs be asynchronous or not.
multi sub llm-graph(%nodes, :e(:$llm-evalutor) = Whatever, Bool:D :a(:$async) = True) is export {
    LLM::Graph.new(:%nodes, :$llm-evalutor, :$async)
}