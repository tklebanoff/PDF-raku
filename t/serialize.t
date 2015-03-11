use v6;
use Test;

use PDF::Tools::Serializer;
use PDF::Object :to-ast;
use PDF::Grammar::Test :is-json-equiv;

sub prefix:</>($name){
    use PDF::Object;
    PDF::Object.compose(:$name)
};

# construct a nasty cyclic structure
my $dict1 = { :ID(1) };
my $dict2 = { :ID(2) };
# create circular hash ref
$dict2<SelfRef> := $dict2;

my $array = [ $dict1, $dict2 ];
my $root-obj = PDF::Object.compose( :$array );
# create circular array reference
$root-obj[2] := $root-obj;

# our serializer should create indirect refs to resolove the above
my $result = $root-obj.serialize;
my $s-objects = $result<objects>;
is +$s-objects, 2, 'expected number of objects';

my $body = {
    :Type(/'Catalog'),
    :Pages{
            :Type(/'Pages'),
            :Kids[ { :Type(/'Page'),
                     :Resources{ :Font{ :F1{ :Encoding(/'MacRomanEncoding'),
                                             :BaseFont(/'Helvetica'),
                                             :Name(/'F1'),
                                             :Type(/'Font'),
                                             :Subtype(/'Type1')},
                                 },
                                 :Procset[ /'PDF',  /'Text' ],
                     },
                     :Contents( PDF::Object.compose( :stream{ :encoded("BT /F1 24 Tf  100 250 Td (Hello, world!) Tj ET") } ) ),
                   }
                ],
            :Count(1),
    },
    :Outlines{ :Type(/'Outlines'), :Count(0) },
    };

my $serializer = PDF::Tools::Serializer.new;
$serializer.analyse( $body );
my $root = $serializer.freeze( $body );
my $objects = $serializer.ind-objs;
PDF::Object.post-process( $objects );

sub infix:<object-order-ok>($obj-a, $obj-b) {
    my ($obj-num-a, $gen-num-a) = @( $obj-a.value );
    my ($obj-num-b, $gen-num-b) = @( $obj-b.value );
    my $ok = $obj-num-a < $obj-num-b
        || ($obj-num-a == $obj-num-b && $gen-num-a < $gen-num-b);
    die  "objects out of sequence: $obj-num-a $gen-num-a R is not <= $obj-num-a $gen-num-b R"
         unless $ok;
    $obj-b
}

ok ([object-order-ok] @$objects), 'objects are in order';
is +$objects, 6, 'number of objects';
is-json-equiv $objects[0], (:ind-obj[1, 0, :dict{
                                               Type => { :name<Catalog> },
                                               Pages => :ind-ref[2, 0],
                                               Outlines => :ind-ref[6, 0],
                                             },
                                   ]), 'root object';

is-json-equiv $objects[2], (:ind-obj[3, 0, :dict{
                                              Resources => :dict{Procset => :array[ :name<PDF>, :name<Text>],
                                              Font => :dict{F1 => :ind-ref[4, 0]}},
                                              Type => :name<Page>,
                                              Contents => :ind-ref[5, 0],
                                              Parent => :ind-ref[2, 0],
                                               },
                                   ]), 'page object';

done;