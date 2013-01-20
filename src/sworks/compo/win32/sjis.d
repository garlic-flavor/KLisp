/** SHIFT-JIS の扱いに。
 * \version      0.0005 dmd2.055
 * \date         2011-Sep-21 02:47:54
 * \author       KUMA
 * \par license:
 * CC0
 */
module sworks.compo.win32.sjis;

import std.array, std.ascii, std.exception, std.conv, std.utf;
private import std.c.windows.windows;
public import sworks.compo.util.strutil;

// スタックトレースの文字列中に、たまに不正な文字が混入するため。
wstring toUTF16Nothrow(T)( const(T)[] str )
	if( is( T == char ) || is( T == wchar ) || is( T == dchar ) )
{
	Appender!(wchar[]) result;
	for( size_t i = 0, j = 0 ; i < str.length ; i += j )
	{
		try
		{
			j = str.stride( i );
			result.put( str[ i .. i+j ].toUTF16 );
		}
		catch( UTFException t ){ result.put( "■" ); }
		if( 0 == j ) j = 1;
	}
	return result.data.idup;
}

// 文字列を SHIFT-JIS文字列に.
jstring toMBS( T )( T msg, int codePage = 0 )
	if( is( T : const(char)[] ) || is( T : const(wchar)[] ) || is( T : const(dchar)[] )
		|| is( T : const(jchar)[] ) )
{
	static if( is( T == jchar ) ) return msg.j;

	bool ASCIIOnly = true;
	for( size_t i = 0 ; i < msg.length && ASCIIOnly ; i++ ) ASCIIOnly = msg[i].isASCII;
	if( ASCIIOnly ) return msg.to!string.j;

	auto str16 = msg.toUTF16Nothrow;
	auto result = new char[ WideCharToMultiByte( codePage, 0, str16.ptr, str16.length, null, 0
	                                           , null, null ) ];

	enforce( 0 < result.length && result.length == WideCharToMultiByte( codePage, 0, str16.ptr
	       , str16.length, result.ptr, result.length, null, null ) );
	return result.j;
}
jstring toMBS( T )( T msg, int codePage = 0 )
	if( !is( T : const(char)[] ) && !is( T : const(wchar)[] ) && !is( T : const(dchar)[] )
		&& !is( T : const(jchar)[] ) )
{
	return msg.to!wstring.toMBS( codePage );
}

// 文字列をSHIFT-JISのNull終端文字列に。
const(byte)* toMBSz(T)( T msg, int codePage = 0 )
	if( is( T : const(char)[] ) || is( T : const(wchar)[] ) || is( T : const(dchar)[] )
		|| is( T : const(jchar)[] ) )
{
	static if( is( T == jchar ) ) return ( msg ~ [ 0 ] ).ptr.jz;

	bool ASCIIOnly = true;
	for( size_t i = 0 ; i < msg.length && ASCIIOnly ; i++ ) ASCIIOnly = msg[i].isASCII;
	if( ASCIIOnly ) return msg.toUTF8z.jz;

	auto str16 = msg.to!wstring;
	auto result = new char[ WideCharToMultiByte( codePage, 0, str16.ptr, str16.length, null, 0
	                                           , null, null ) + 1 ];

	enforce( 1 < result.length && result.length - 1 == WideCharToMultiByte( codePage, 0, str16.ptr
	       , str16.length, result.ptr, result.length - 1, null, null ) );
	return result.ptr.jz;
}

const(byte)* toMBSz(T)( T msg, int codePage = 0 )
	if( !is( T : const(char)[] ) && !is( T : const(wchar)[] ) && !is( T : const(dchar)[] )
		&& !is( T : const(jchar)[] ) )
{
	return msg.to!wstring.toMBSz( codePage );
}

// SHIFT-JIS文字列をUTF文字列に
immutable(CHAR)[] fromMBS(CHAR)( const(jchar)[] msg, int codePage = 0 )
	if( is( T == char ) || is( T == wchar ) || is( T == dchar ) || is( T == jchar ) )
{
	static if( is( CHAR == jchar ) ) return msg;

	bool ASCIIOnly = true;
	for( size_t i = 0 ; i < msg.length && ASCIIOnly ; i++ ) ASCIIOnly = msg[i].isASCII;
	if( ASCIIOnly ) return msg.c.to!(immutable(CHAR)[]);

	auto result = new wchar[ MultiByteToWideChar( codePage, 0, msg.ptr, msg.length, null, 0 ) ];
	enforce( 0 < result.length && result.length == MultiByteToWideChar( codePage, 0, msg.ptr
	       , msg.length, result.ptr, result.length ) );
	return result.to!(immutable(CHAR)[]);
}

// Null終端SHIFT-JIS文字列をUTF文字列に。
immutable(CHAR)[] fromMBSz(CHAR)( const(jchar)* msg, int codePage = 0 )
	if( is( T == char ) || is( T == wchar ) || is( T == dchar ) || is( T == jchar ) )
{
	size_t i = 0;
	static if( is( CHAR == jchar ) )
	{
		for( ; msg[i] != 0 ; i++ ){}
		return msg[ 0 .. i ].j;
	}

	bool ASCIIOnly = true;
	for( ; msg[i] != 0 && ASCIIOnly ; i++ ) ASCIIOnly = msg[i].isASCII;
	if( ASCIIOnly ) return msg[ 0 .. i ].c.to!(immutable(CHAR)[]);

	auto result = new wchar[ MultiByteToWideChar( codePage, 0, msg, -1, null, 0 ) ];
	enforce( 0 < result.length && result.length == MultiByteToWideChar( codePage, 0, msg.ptr
	       , msg.length, result.ptr, result.length ) );
	return result.to!(immutable(CHAR)[]);
}


debug( sjis ):

import std.stdio;
void main()
{
	writeln( "日本語".toMBS.c );
}