use v6;

use PDF::Storage::Input;

class PDF::Storage::Input::IOH
    is PDF::Storage::Input {

    has IO::Handle $.value is required handles <read eof close>;
    has Str $!str;
    has UInt $.codes is rw;

    multi submethod TWEAK {
        $!value.seek( 0, SeekFromEnd );
        $!codes = $!value.tell;
        $!value.seek( 0, SeekFromBeginning );
    }

    multi method Str {
        $!str //= do {
            $!value.seek( 0, SeekFromBeginning );
            $.value.slurp-rest;
        }
    }

    multi method subbuf( WhateverCode $whence!, |c --> Buf) {
        my UInt $from = $whence( $.codes );
        $.subbuf( $from, |c );
    }

    multi method subbuf( UInt $from!, UInt $length = $.codes - $from + 1 --> Buf) {
        with $!str {i
            .substr-rw( $from, $length )
        }
        else {
            $!value.seek( $from, SeekFromBeginning );
            $!value.read( $length );
        }
    }

    method substr(|c) {
	$.subbuf(|c).decode('latin-1');
    }
}
