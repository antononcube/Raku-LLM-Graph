#!/usr/bin/env raku
use v6.d;

use LLM::Graph;
use LLM::Functions;

#==========================================================

proto sub toy-llm($form) {*}

multi sub toy-llm(Str:D $draft) {
    toy-llm({critique => '', critique-iteration => 0, revision => $draft, revision-iteration => 0})
}

multi sub toy-llm(%form) {
    if %form<critique-iteration> ≤ %form<revision-iteration> {
        %form<critique> = do given %form<critique-iteration> {
            when $_ == 0  { 'Needs a clearer thesis and one concrete example.' }
            when $_ == 1  { 'Much better. Add a concise closing sentence.' }
            default { "Looks good." }
        }
        %form<critique-iteration> += 1;
        return %form
    }
    %form<revision> ~= "\n[Revision applied: tightened and clarified.]";
    %form<revision-iteration> += 1;
    return %form
}

#==========================================================

my %generation-rules =
        generate => {
                eval-function => sub ($topic) {
                        my $draft = "Draft (iteration 1) on $topic:\n" ~
                                "- Thesis: $topic matters.\n" ~
                                "- Point: Provide one benefit.\n" ~
                                "- Example: TBD.\n";
                        return $draft;
                }
        }
;

#==========================================================

my %revision-rules =
        decide => {
            eval-function => sub ($text) {
                !(
                $text ~~ Str:D && $text.contains("Looks good") ||
                        $text ~~ Map:D && $text<critique>.contains("Looks good")
                )
            }
        },

        critique => {
            eval-function => sub ($text) {
                return toy-llm($text) if $text ~~ Str:D;

                my $form = $text.clone;
                $form<critique-iteration> += $form<critique-iteration>;

                return toy-llm($form);
            },

            test-function => sub ($decide) { $decide.raku.lc.contains('true') }
        },

        revise => {
            eval-function => sub ($text, $critique) {
                my $form = $critique.clone;
                $form = toy-llm($form);
                return $form;
            },

            test-function => sub ($critique) { $critique.defined }
        },

        finalize => {
            eval-function => sub ($text, $revise) { $revise.defined ?? $revise !! $text}
        }
;

#==========================================================

my $g1 = LLM::Graph.new(%generation-rules):!async;
my $g2 = LLM::Graph.new(%revision-rules):!async;

say (:$g1, :$g2);

$g1.eval({ topic => "why cyclic graphs help with iterative writing" });

my $text = $g1.nodes<generate><result>;

say (:$text);

$g2.eval({ :$text });

say $g2.nodes<finalize><result>;

#==========================================================

$g1.clear;
$g2.clear;

$g1.eval({ topic => "why cyclic graphs helpe with iterative writin??g" });
$text = $g1.nodes<generate><result>;

for (^2) -> $iter {
    say '-' x 10, $iter, '-' x 10;
    $g2.clear;
    $g2.eval({:$text});
    my $revision = $g2.nodes<finalize><result>;
    last if $revision eq $text;
    $text = $revision
}

say $text;