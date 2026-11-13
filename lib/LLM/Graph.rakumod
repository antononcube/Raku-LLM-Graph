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
    has Bool $.progress-reporting is rw = False;
    has @.cycle-plans is rw = ();

    constant @ALLOWED_KEYS = <eval-function llm-function listable-llm-function input test-function test-function-input initial-value termination-function max-iterations spec-type wrapper result test-function-result initial-value-input termination-function-input iteration-count termination-reason>;
    constant %ALLOWED = @ALLOWED_KEYS.map({ $_ => True }).hash;

    #======================================================
    # Creators
    #======================================================
    submethod BUILD(:%!nodes = %(),
                    :$!graph = Whatever,
                    :$!llm-evaluator = Whatever,
                    Bool:D :$!async = True,
                    Bool:D :$!progress-reporting = False
                    ) {
        if $!llm-evaluator.isa(Whatever) {
            $!llm-evaluator = llm-evaluator(llm-configuration(Whatever));
        }
    }


    multi method new(%nodes,
                     :e(:$llm-evaluator) = Whatever,
                     Bool:D :a(:$async) = True,
                     Bool:D :progress(:$progress-reporting) = False
                     ) {
        self.bless(:%nodes, graph => Whatever, :$llm-evaluator, :$async, :$progress-reporting);
    }

    multi method new(:%nodes!,
                     :e(:$llm-evaluator) = Whatever,
                     Bool:D :a(:$async) = True,
                     Bool:D :progress(:$progress-reporting) = False
                     ) {
        self.bless(:%nodes, graph => Whatever, :$llm-evaluator, :$async, :$progress-reporting);
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
                $_.value<initial-value-input>:delete;
                $_.value<termination-function-input>:delete;
                $_.value<iteration-count>:delete;
                $_.value<termination-reason>:delete;
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
                        $_.value<initial-value-input>:delete;
                        $_.value<termination-function-input>:delete;
                        $_.value<iteration-count>:delete;
                        $_.value<termination-reason>:delete;
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
                if ($val<initial-value>:exists) && $val<initial-value> !~~ Callable:D {
                    @errors.push(
                            "Rule '$name' has invalid spec -- " ~
                            'node\'s initial value must be a Callable:D object.')
                }
                if ($val<termination-function>:exists) && $val<termination-function> !~~ Callable:D {
                    @errors.push(
                            "Rule '$name' has invalid spec -- " ~
                            'node\'s termination function must be a Callable:D object.')
                }
                if ($val<max-iterations>:exists) &&
                        !($val<max-iterations> ~~ Int:D && $val<max-iterations> > 0) {
                    @errors.push(
                            "Rule '$name' has invalid spec -- " ~
                            'node\'s max iterations must be a positive Int:D value.')
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
                    %!nodes{$k} = %( eval-function => { start llm-synthesize($node, :$!llm-evaluator) }, spec-type => Str )
                }

                when ($_ ~~ Str:D || $_ ~~ (Array:D | List:D | Seq:D) && $_.all ~~ Str:D) && !self.async {
                    %!nodes{$k} = %( llm-function => llm-function($_, :$!llm-evaluator), spec-type => Str )
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
                    # Handle "shortcut" specs
                    my %rename =
                            llm-sub => 'llm-function',
                            eval-sub => 'eval-function',
                            test-sub => 'test-function',
                            listable-llm-sub => 'listable-llm-function';

                    for %rename.kv -> $old, $new {
                        if $_{$old}:exists {
                            $_{$new} = $_{$old};
                            $_{$old}:delete;
                        }
                    }

                    # Determine spec type
                    my $spec-type = do if $_<spec-type>:exists {
                        $_<spec-type>
                    } else {
                        $_<eval-function>:exists ?? Callable !! LLM::Function
                    }

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

        die self.node-spec-errors().join("\n")
        unless self.has-valid-node-specs;

        # For each node get the input arguments
        my %funcArgs = %!nodes.map({ $_.key => $_.value<eval-function> // $_.value<llm-function> // $_.value<listable-llm-function> });
        %funcArgs .= map({ $_.key => sub-info($_.value)<parameters>.map(*<name>).List });

        # For each node get the test function input arguments (if any)
        my %testArgs = %!nodes.grep({ $_.value<test-function> }).map({ $_.key => $_.value<test-function> });
        %testArgs .= map({ $_.key => sub-info($_.value)<parameters>.map(*<name>).List });

        # Loop-control functions have their own dependency classes. 
        # Initial values are evaluated once before a loop, and 
        # termination functions are evaluated after each completed iteration.
        my %initialArgs = %!nodes.grep({ $_.value<initial-value> }).map({ $_.key => $_.value<initial-value> });
        %initialArgs .= map({ $_.key => sub-info($_.value)<parameters>.map(*<name>).List });

        my %terminationArgs = %!nodes.grep({ $_.value<termination-function> }).map({ $_.key => $_.value<termination-function> });
        %terminationArgs .= map({ $_.key => sub-info($_.value)<parameters>.map(*<name>).List });

        # Add named args
        ## If the graph input has hashmaps that have keys that also graph node names,
        ## then the edges derivation can get confused about node dependencies.
        my %external-named-args = %named-args.grep({ !(%!nodes{$_ .key}:exists) }).Hash;
        my %args = %funcArgs.clone , %external-named-args.nodemap(*.raku) , {'$_' => $pos-arg // '(Any)'};
        my %allArgs = merge-hash(%args , %testArgs, :positional-append);
        %allArgs = merge-hash(%allArgs, %initialArgs, :positional-append);
        %allArgs = merge-hash(%allArgs, %terminationArgs, :positional-append);

        # Make edges
        my @edges = (%allArgs.keys X %allArgs.keys).map( -> ($k1, $k2) {
                my $v2 = %allArgs{$k2};
                if $k1 ∈ $v2 || $k1 ∈ $v2».subst(/ ^ <[$%@]> /) {
                    my $weight = +((%funcArgs{$k2}:exists) && ($k1 ∈ %funcArgs{$k2} || $k1 ∈ %funcArgs{$k2}».subst(/ ^ <[$%@]> /)));
                    $weight += 2 * +((%testArgs{$k2}:exists) && ($k1 ∈ %testArgs{$k2} || $k1 ∈ %testArgs{$k2}».subst(/ ^ <[$%@]> /)));
                    $weight += 4 * +((%initialArgs{$k2}:exists) && ($k1 ∈ %initialArgs{$k2} || $k1 ∈ %initialArgs{$k2}».subst(/ ^ <[$%@]> /)));
                    $weight += 8 * +((%terminationArgs{$k2}:exists) && ($k1 ∈ %terminationArgs{$k2} || $k1 ∈ %terminationArgs{$k2}».subst(/ ^ <[$%@]> /)));
                    %( from => $k1, to => $k2, :$weight )
                }
            });

        # Make graph
        $!graph = Graph.new(@edges):d;

        # Identify and validate strongly connected components. 
        # Graph.connected-components is Tarjan Strongly Connected Components (SCCs) for directed graphs. 
        # A singleton component is cyclic only when it has an explicit self-reference.
        @!cycle-plans = self!make-cycle-plans;

        return self;
    }

    method !make-cycle-plans() {
        my @plans;

        for $!graph.connected-components -> @component {
            my @cycle-nodes = @component.grep({ %!nodes{$_}:exists }).Array;
            next unless @cycle-nodes.elems;

            my $is-cycle = @cycle-nodes.elems > 1 ||
                    (@cycle-nodes.elems == 1 && $!graph.has-edge(@cycle-nodes[0], @cycle-nodes[0]));
            next unless $is-cycle;

            my @anchors = @cycle-nodes.grep({ %!nodes{$_}<initial-value>:exists }).Array;
            die 'A cyclic component requires exactly one node with "initial-value": ' ~ @cycle-nodes.sort.join(', ') ~ '.'
            unless @anchors.elems == 1;

            my $anchor = @anchors[0];
            die "Loop anchor '$anchor' requires a positive \"max-iterations\" value."
            unless %!nodes{$anchor}<max-iterations>:exists &&
                    %!nodes{$anchor}<max-iterations> ~~ Int:D &&
                    %!nodes{$anchor}<max-iterations> > 0;

            my @misplaced-controls = @cycle-nodes.grep({
                $_ ne $anchor &&
                        ((%!nodes{$_}<initial-value>:exists) ||
                         (%!nodes{$_}<termination-function>:exists) ||
                         (%!nodes{$_}<max-iterations>:exists))
            }).Array;
            die 'Loop controls must be specified on the anchor node ' ~
                    "'$anchor'; found controls on " ~ @misplaced-controls.sort.join(', ') ~ '.'
            if @misplaced-controls.elems;

            # The anchor carries the previous iteration's state. 
            # Removing it must leave an acyclic body, otherwise 
            # there are multiple feedback points and the evaluation order is ambiguous.
            my @body = @cycle-nodes.grep(* ne $anchor).Array;
            if @body.elems {
                my @body-edges = $!graph.edges(:dataset).grep({
                    $_<from> ∈ @body && $_<to> ∈ @body
                }).Array;
                my $body-graph = Graph.new(@body, @body-edges):d;
                my $has-residual-cycle = $body-graph.connected-components.grep(-> @part {
                    @part.elems > 1 || (@part.elems == 1 && $body-graph.has-edge(@part[0], @part[0]))
                }).elems > 0;
                die 'Cyclic component has more than one feedback loop after removing anchor ' ~
                        "'$anchor': " ~ @cycle-nodes.sort.join(', ') ~ '.'
                if $has-residual-cycle;
            }

            @plans.push({
                anchor => $anchor,
                cycle-nodes => @cycle-nodes.Array,
                body-nodes => @body,
                max-iterations => %!nodes{$anchor}<max-iterations>
            });
        }

        # Loop controls are meaningful only on a cyclic component.
        for %!nodes.kv -> $name, %node {
            if ((%node<initial-value>:exists) || (%node<termination-function>:exists) || (%node<max-iterations>:exists)) &&
                    !@plans.first({ $name ∈ $_<cycle-nodes> }, :k).defined {
                die "Loop controls on node '$name' require a cyclic dependency component.";
            }
        }

        return @plans.Array;
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

    method eval-threaded-func(&func, %inputs, :$pos-arg = '') {

        my @listInputs = %inputs.grep({
            $_.value ~~ (Array:D | List:D | Seq:D)
        }).Array;

        my $usePosArg = @listInputs.elems == 0 && $pos-arg ~~ (Array:D | List:D | Seq:D);

        die 'A listable LLM function requires exactly one list input.'
        unless @listInputs.elems == 1 || $usePosArg;

        my @items = $usePosArg ?? $pos-arg.List !! @listInputs.head.value.List;
        my $inputName = $usePosArg ?? Nil !! @listInputs.head.key;

        # Wrap every invocation in a Promise so both synchronous and asynchronous
        # functions can be handled uniformly. Awaiting a Promise returned by the
        # function avoids producing nested Promises.
        my @jobs = @items.map(-> $item {
            start {
                my %itemInputs = %inputs.clone;
                %itemInputs{$inputName} = $item unless $usePosArg;

                my $result = self.eval-func(
                        &func,
                        %itemInputs,
                        pos-arg => $usePosArg ?? $item !! $pos-arg);

                $result ~~ Promise:D ?? await($result) !! $result
            }
        }).Array;

        # Keep this node asynchronous so independent graph branches can continue
        # while its element-wise evaluations are running.
        return start {
            await(Promise.allof(@jobs));
            @jobs.map(*.result).Array
        };
    }

    #======================================================
    # Cyclic evaluation
    #======================================================

    method eval-cycle-inputs(@dependencies, :$pos-arg = '', :%named-args = %()) {
        my %inputs = @dependencies.map({
            $_ => self.eval-node($_, :$pos-arg, :%named-args)
        });

        my @inputPromises = %inputs.grep({ $_.value ~~ Promise:D })».value;
        if @inputPromises {
            my $allDone = Promise.allof(@inputPromises);
            note "Awaiting for the results of {%inputs.grep({ $_.value ~~ Promise:D })».key}"
            if $!progress-reporting;
            await($allDone);
            %inputs .= map({ $_.value ~~ Promise:D ?? ($_.key => $_.value.result) !! $_ });
        }

        return %inputs;
    }

    method invoke-cycle-function($node, %inputs, :$pos-arg = '') {
        my $result;
        if %!nodes{$node}<listable-llm-function>:exists {
            $result = self.eval-threaded-func(
                    %!nodes{$node}<listable-llm-function>,
                    %inputs,
                    :$pos-arg);
        } else {
            my &func = %!nodes{$node}<eval-function> // %!nodes{$node}<llm-function>;
            $result = self.eval-func(&func, %inputs, :$pos-arg);
        }

        if $result ~~ Promise:D {
            await($result);
            $result = $result.result;
        }
        return $result;
    }

    method eval-cycle-initial-value($anchor, :$pos-arg = '', :%named-args = %()) {
        # A supplied anchor value starts a new run, rather than bypassing the loop.
        # It intentionally takes precedence over the initial-value callable.
        return %named-args{$anchor} if %named-args{$anchor}:exists;

        my @dependencies = |(%!nodes{$anchor}<initial-value-input> // []);
        my %inputs = self.eval-cycle-inputs(@dependencies, :$pos-arg, :%named-args);
        my $result = self.eval-func(%!nodes{$anchor}<initial-value>, %inputs, :$pos-arg);
        if $result ~~ Promise:D {
            await($result);
            $result = $result.result;
        }
        return $result;
    }

    method eval-cycle-anchor($anchor, :$pos-arg = '', :%named-args = %()) {
        %!nodes{$anchor}<test-function-result>:delete;
        if !self.eval-test-node($anchor, :$pos-arg, :%named-args) {
            return %!nodes{$anchor}<result>;
        }

        my @dependencies = |(%!nodes{$anchor}<input> // []);
        my %inputs = self.eval-cycle-inputs(@dependencies, :$pos-arg, :%named-args);
        return self.invoke-cycle-function($anchor, %inputs, :$pos-arg);
    }

    method cycle-terminated($anchor, :$pos-arg = '', :%named-args = %()) {
        return False without %!nodes{$anchor}<termination-function>;

        my @dependencies = |(%!nodes{$anchor}<termination-function-input> // []);
        my %inputs = self.eval-cycle-inputs(@dependencies, :$pos-arg, :%named-args);
        my $result = self.eval-func(%!nodes{$anchor}<termination-function>, %inputs, :$pos-arg);
        if $result ~~ Promise:D {
            await($result);
            $result = $result.result;
        }
        return so $result;
    }

    method eval-cycle(%plan, :$pos-arg = '', :%named-args = %()) {
        my $anchor = %plan<anchor>;
        my @cycle-nodes = |%plan<cycle-nodes>;
        my @body-nodes = |%plan<body-nodes>;
        my %iteration-args = %named-args.clone;
        %iteration-args{$anchor}:delete;

        # A cyclic component is stateful only within one eval call. 
        # Do not reuse prior-run state, but preserve an explicitly supplied anchor.
        for @cycle-nodes -> $node {
            %!nodes{$node}<result>:delete;
            %!nodes{$node}<test-function-result>:delete;
        }

        %!nodes{$anchor}<result> = self.eval-cycle-initial-value(
                $anchor, :$pos-arg, :%named-args);

        my $iterations = 0;
        my $termination-reason = 'max-iterations';
        for ^%plan<max-iterations> {
            # Body values are recomputed for every pass; 
            # the anchor remains available as the state of the previous pass until it is updated.
            for @body-nodes -> $node {
                %!nodes{$node}<result>:delete;
                %!nodes{$node}<test-function-result>:delete;
                self.eval-node($node, :$pos-arg, named-args => %iteration-args);
            }

            %!nodes{$anchor}<result> = self.eval-cycle-anchor(
                    $anchor, :$pos-arg, named-args => %iteration-args);
            $iterations++;

            if self.cycle-terminated($anchor, :$pos-arg, named-args => %iteration-args) {
                $termination-reason = 'termination-function';
                last;
            }
        }

        %!nodes{$anchor}<iteration-count> = $iterations;
        %!nodes{$anchor}<termination-reason> = $termination-reason;
        return self;
    }

    # This method's code is almost the same as the code of eval-node -- should be refactored.
    method eval-test-node($node, :$pos-arg = '', :%named-args = %()) {

        return $pos-arg if $node eq '$_';

        return %named-args{$node} if %named-args{$node}:exists;

        return True without %!nodes{$node}<test-function>;

        return %!nodes{$node}<test-function-result> with %!nodes{$node}<test-function-result>;

        my %inputs;
        if %!nodes{$node}<test-function-input> {
            %inputs = %!nodes{$node}<test-function-input>.map({ $_ => self.eval-node($_, :$pos-arg, :%named-args) })
        }

        # Select the inputs that are promises
        my @inputPromises = %inputs.grep({ $_.value ~~ Promise:D })».value;

        # Wait for all promises to finish
        if @inputPromises {
            my $allDone = Promise.allof(@inputPromises);

            note "Test function awaiting for the results of {%inputs.grep({ $_.value ~~ Promise:D })».key}"
            if $!progress-reporting;

            await($allDone);
            %inputs .= map({ $_.value ~~ Promise:D ?? ($_.key => $_.value.result) !! $_ });
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

        return %named-args{$node} if %named-args{$node}:exists;

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

            note "Awaiting for the results of {%inputs.grep({ $_.value ~~ Promise:D })».key}"
            if $!progress-reporting;

            await($allDone);
            %inputs .= map({ $_.value ~~ Promise:D ?? ($_.key => $_.value.result) !! $_ });
        }

        # Node function info
        my $result;
        if %!nodes{$node}<listable-llm-function>:exists {
            $result = self.eval-threaded-func(
                    %!nodes{$node}<listable-llm-function>,
                    %inputs,
                    :$pos-arg);
        } else {
            my &func = %!nodes{$node}<eval-function> // %!nodes{$node}<llm-function>;
            $result = self.eval-func(&func, %inputs, :$pos-arg);
        }

        # Register result
        if self.graph.vertex-out-degree($node) == 0 && $result ~~ Promise:D {

            note "Awaiting for the final node ⎡$node⎦" if $!progress-reporting;

            await($result);
            $result = $result.result;
        }
        %!nodes{$node}<result> = $result;

        return $result;
    }

    sub is-nodes-spec($x) { $x.isa(Whatever) || $x ~~ Str:D || $x ~~ (Array:D | List:D | Seq:D) && $x.all ~~ Str:D }

    multi method eval($arg, $nodes where is-nodes-spec($nodes) = Whatever) {
        # $arg cannot be Pair:D -- see: eval(%args, $nodes, *%stray-args)
        return self.eval({'$_' => $arg}, :$nodes);
    }

    multi method eval($dummy, $nodes where !is-nodes-spec($nodes), *%stray-args) {
        die 'The second argument of the method eval is expected to be a node name, a list of node names, or Whatever.';
    }

    multi method eval(%args = %(), $nodes where is-nodes-spec($nodes) = Whatever, *%stray-args) {

        my %named-args = merge-hash(%stray-args, %args);
        my $pos-arg = %named-args<$_>;

        # Test functions that depend nodes that depend on the arguments
        # and have assigned values have to be cleared.
        # Clearing all nodes with test functions for now.

        # Nodes with test functions
        my @tf-nodes = %!nodes.grep({ $_.value<test-function>:exists })».key;
        self.clear(@tf-nodes);

        # Make the graph if not made already
        # Maybe it should be always created.
        if $!graph.isa(Whatever) { self.create-graph($pos-arg, %named-args) }

        # Determine result nodes
        my @resNodes = do given $nodes {
            when Whatever {
                my @terminal-nodes = $!graph.vertex-out-degree(:p).grep({ $_.value == 0 })».key;
                my @terminal-anchors;
                for @!cycle-plans -> %plan {
                    my @cycle-nodes = |%plan<cycle-nodes>;
                    if @cycle-nodes.grep(-> $node {
                        ($!graph.adjacency-map{$node} // {}).keys.grep({ $_ ∉ @cycle-nodes }).elems > 0
                    }).elems == 0 {
                        @terminal-anchors.push(%plan<anchor>);
                    }
                }
                [|@terminal-nodes, |@terminal-anchors].unique.Array
            }

            when $_ ~~ Str:D && (%!nodes{$_}:exists) {
                [$nodes, ]
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
            %!nodes{$k} = [|%v , input => [], test-function-input => [], initial-value-input => [], termination-function-input => [], result => Nil].Hash;
            with $gr.adjacency-map{$k} {
                if %v<test-function>:exists {
                    # Edge weights are dependency bit flags: 1 = node
                    # function, 2 = test, 4 = initializer, 8 = terminator.
                    %!nodes{$k}<test-function-input> = $gr.adjacency-map{$k}.grep({ $_.value +& 2 }).Hash.keys.Array;
                }
                %!nodes{$k}<input> = $gr.adjacency-map{$k}.grep({ $_.value +& 1 }).Hash.keys.Array;
                %!nodes{$k}<initial-value-input> = $gr.adjacency-map{$k}.grep({ $_.value +& 4 }).Hash.keys.Array;
                %!nodes{$k}<termination-function-input> = $gr.adjacency-map{$k}.grep({ $_.value +& 8 }).Hash.keys.Array;
            }
        }

        # Identify which cycle components are needed for the requested output nodes.
        # This preserves the existing partial-evaluation behavior.
        my %needed;
        sub mark-dependencies($node) {
            return if %needed{$node}:exists;
            %needed{$node} = True;
            for ($gr.adjacency-map{$node} // {}).keys -> $dependency {
                mark-dependencies($dependency);
            }
        }
        mark-dependencies($_) for @resNodes;

        # Components form a DAG. Evaluate cycles only after any other needed
        # cyclic component on which they depend has completed.
        my @pending = @!cycle-plans.grep({
            (%needed.keys (&) $_<cycle-nodes>).elems > 0
        }).Array;
        my %cycle-anchors = @pending.map({ $_<anchor> => True }).Hash;
        while @pending {
            my $ready-index;
            for ^@pending.elems -> $i {
                my %candidate = @pending[$i];
                my @dependencies = %candidate<cycle-nodes>.map({
                    ($gr.adjacency-map{$_} // {}).keys
                }).flat.unique.Array;
                my $blocked = False;
                for ^@pending.elems -> $j {
                    next if $i == $j;
                    if (@dependencies (&) @pending[$j]<cycle-nodes>).elems {
                        $blocked = True;
                        last;
                    }
                }
                unless $blocked {
                    $ready-index = $i;
                    last;
                }
            }
            die 'Unable to establish an evaluation order for cyclic components.'
            unless $ready-index.defined;

            my %plan = @pending[$ready-index];
            @pending.splice($ready-index, 1);
            self.eval-cycle(%plan, :$pos-arg, :%named-args);
        }

        # For each result node recursively evaluate its inputs
        my %post-cycle-named-args = %named-args.clone;
        %post-cycle-named-args{$_}:delete for %cycle-anchors.keys;
        for @resNodes -> $node {
            # Make sure each evaluated node has the result in its hashmap
            self.eval-node($node, :$pos-arg, named-args => %post-cycle-named-args)
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
#| C<:progress(:$progress-reporting)> -- Should evaluation progress be reported or not.
multi sub llm-graph(%nodes,
                    :e(:$llm-evaluator) = Whatever,
                    Bool:D :a(:$async) = True,
                    Bool:D :progress(:$progress-reporting) = False) is export {
    LLM::Graph.new(:%nodes, :$llm-evaluator, :$async, :$progress-reporting)
}
