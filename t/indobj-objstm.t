use v6;
use Test;

plan 4;

use PDF::Basic::IndObj;
use PDF::Basic::Unbox;

use PDF::Grammar::PDF;
use PDF::Grammar::PDF::Actions;
use PDF::Basic;

my $actions = PDF::Grammar::PDF::Actions.new;

my $input = 't/pdf/ind-obj-ObjStm-Flate.in'.IO.slurp( :enc<latin-1> );
PDF::Grammar::PDF.parse($input, :$actions, :rule<ind-obj>)
    // die "parse failed";
my $ast = $/.ast;
my %params = %( PDF::Basic::Unbox.unbox( |%$ast ) );
my $ind-obj = PDF::Basic::IndObj.indobj-new( |%params, :$input );
isa_ok $ind-obj, PDF::Basic::IndObj::ObjStm;

my $objstm;
lives_ok { $objstm = $ind-obj.decode }, 'basic content decode - lives';

my $expected-objstm = [
    { :obj-num(16), object => :dict{FirstChar => :int(111),
                                    FontDescriptor => :ind-ref[15, 0],
                                    Widths => :array[ :int(600)],
                                    Type => :name<Font>,
                                    Encoding => :name<WinAnsiEncoding>,
                                    LastChar => :int(111),
                                    Subtype => :name<TrueType>,
                                    BaseFont => :name<CourierNewPSMT>},
    },
    { :obj-num(17), object => :dict{LastChar => :int(32),
                                    Widths => :array[ :int(250) ],
                                    Encoding => :name<WinAnsiEncoding>,
                                    Subtype => :name<TrueType>,
                                    FirstChar => :int(32),
                                    BaseFont => :name<TimesNewRomanPSMT>,
                                    FontDescriptor => :ind-ref[14, 0],
                                    Type => :name<Font>},
    },
    ];

is_deeply $objstm, $expected-objstm, 'decoded index as expected';
my $objstm-recompressed = $ind-obj.encode;

my $ind-obj2 = PDF::Basic::IndObj.indobj-new( |%params);
my $objstm-roundtrip = $ind-obj2.decode( $objstm-recompressed );

is_deeply $objstm, $objstm-roundtrip, 'encode/decode round-trip';
