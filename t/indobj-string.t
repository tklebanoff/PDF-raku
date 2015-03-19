use v6;
use Test;

plan 13;

use PDF::Tools::IndObj;

use PDF::Grammar::PDF;
use PDF::Grammar::PDF::Actions;
use lib '.';
use t::Object :to-obj;

my $actions = PDF::Grammar::PDF::Actions.new;

my $input = '42 5 obj (a literal string) endobj';
PDF::Grammar::PDF.parse($input, :$actions, :rule<ind-obj>)
    // die "parse failed";
my $ast = $/.ast;
my $ind-obj = PDF::Tools::IndObj.new( |%$ast, :$input );
isa_ok $ind-obj.object, Str;
is $ind-obj.obj-num, 42, '$.obj-num';
is $ind-obj.gen-num, 5, '$.gen-num';
my $content = $ind-obj.content;
isa_ok $content, Pair;
is_deeply to-obj( $content ), 'a literal string', '$.content to-obj';
is_deeply $content, (:literal("a literal string")), '$.content';

$input = '123 4 obj <736E6F6f7079> endobj';
PDF::Grammar::PDF.parse($input, :$actions, :rule<ind-obj>)
    // die "parse failed";
$ast = $/.ast;
$ind-obj = PDF::Tools::IndObj.new( |%$ast, :$input );
isa_ok $ind-obj.object, Str;
is $ind-obj.obj-num, 123, '$.obj-num';
is $ind-obj.gen-num, 4, '$.gen-num';
$content = $ind-obj.content;
isa_ok $content, Pair;
is_deeply to-obj( $content ), 'snoopy', '$.content to-obj';
is_deeply $content, (:hex-string<snoopy>), '$.content';

is_deeply $ind-obj.ast, $ast, 'ast regeneration';
