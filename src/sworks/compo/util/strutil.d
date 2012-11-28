/**
 * Version:      0.002(dmd2.060)
 * Date:         2012-Nov-28 15:55:35
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.compo.util.strutil;

import std.exception;

// SHIFT-JIS の格納に。
struct jchar{ byte bare; alias bare this; }
alias immutable(jchar)[] jstring;
alias immutable(jchar)* jstringz;
alias immutable(wchar)* wstringz;
/// suger
jstring j(T)( T[] str){ return cast(jstring)str; }
jstringz jz(T)( T* strz ){ return cast(jstringz)strz; }
string c(T)( T[] jstr ){ return cast(string)jstr; }


T enstring( T )( T str, lazy string msg = "failure in enstring" )
{
	if( 0 < str.length ) return str;
	else throw new Exception( msg );
}
