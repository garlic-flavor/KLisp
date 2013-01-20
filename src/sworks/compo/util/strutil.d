/**
 * \version      0.0005 dmd2.055
 * \date         2011-Sep-21 02:47:54
 * \author       KUMA
 * \par license:
 * CC0
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
