/** sworks.klisp.klisp_file.IKLispFile 先頭から、1トークンを得る。
 * Version:      0.003(dmd2.060)
 * Date:         2013-Jan-14 02:44:54
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.klisp.token;

import std.array, std.ascii, std.exception, std.conv, std.regex, std.string, std.utf, std.algorithm;
import sworks.klisp.klisp_file;

struct Token
{
	enum TYPE { NULL, NORMAL, SINGLE, STRING, INT, FLOAT, OPEN_BRACKET, CLOSE_BRACKET, EOF }
	TYPE type;
	size_t line;
	const(dchar)[] value;
}

interface IKLispToken
{
	string filename() @property;

	uint nest() @property;
	uint incNest();
	uint decNest();
	Token nextToken();
}

abstract class KLispToken : IKLispToken
{
	IKLispFile file;
	protected uint _nest;

	this( IKLispFile kf ){ this.file = kf; }

	string filename() @property { return null !is file ? file.filename : ""; }

	uint nest() @property { return _nest; }
	uint incNest(){ return ++_nest; }
	uint decNest(){ if( 0 < _nest ) _nest--; return _nest; }

	abstract Token nextToken();

	protected bool adjustNest()
	{
		if     ( file.nest < _nest ) return false;
		else if( _nest < file.nest )
		{
			incNest;
			for( Token t ; ; )
			{
				t = nextToken();
				if( t.type == Token.TYPE.NULL || t.type == Token.TYPE.EOF ) break;
			}
			decNest;
		}
		return true;
	}

	/*
	 * IKLispFile 先頭からトークンを切り出す。空白文字、コメント、ネストの深度を考慮しない。
	 *
	 * Params:
	 *   QUOTE = 文字列を表現する クォート は dchar 1字で構成され、
	 *           開きクォート QUOTE[2n] に対応する閉じクォートは QUOTE[2n+1] であるとする。
	 *
	 *   SINGLE_KEYWORD = 一字でトークンを構成する。
	 *
	 * Return:
	 *   戻り値に使われているバッファは再利用される可能性がある。必要なら dup をとる。
	 */
	protected Token chomp_token( dstring QUOTE, dstring SINGLE_KEYWORD )()
	{
		// トークンのパース中にこれが表われたらトークンが正しく終了される。
		enum TOKEN_STOPPER = " \r\n\t\0　"d ~ dchar.init ~ SINGLE_KEYWORD ~ QUOTE;

		Token result;
		// メモのクリア
		file.flush;
		// 一字切り出し
		int i;
		auto line = file.line;
		auto d = file.push;

		// eof
		if( dchar.init == d || '\0' == d ) result = Token( Token.TYPE.EOF, line );
		// カッコ
		else if( DEFAULT_BRACKET[0] == d ) result = Token( Token.TYPE.OPEN_BRACKET, line );
		else if( DEFAULT_BRACKET[1] == d ) result = Token( Token.TYPE.CLOSE_BRACKET, line );
		// 文字列
		else if( 0 <= ( i = QUOTE.countUntil(d) ) )
		{
			if( i & 1 ) throw new KLispException( file.filename, file.line, [ d ]
				, "トークン中に予期せぬ文字が表われました。"
					"この文字は閉じクォートとして登録されていますが、現在文字列中ではありません。" );
			assert( i+1 < QUOTE.length );

			auto close_quote = QUOTE[ i + 1 ];
			for( file.flush ; ; )
			{
				d = file.front;
				// eof
				if     ( dchar.init == d )
				{
					auto buf = QUOTE[ i .. i+1 ] ~ file.stack;
					if( 32 < buf.length ) buf = buf[ 0 .. 32 ] ~ " ...";
					throw new KLispException( file.filename, line, buf, "文字列に閉じカッコがありません。" );
				}
				// エスケープシーケンス
				else if( '\\' == d )
				{
					d = file.discard;
					if     ( 'n' == d ) file.push( '\n' );
					else if( 'r' == d ) file.push( '\r' );
					else if( 't' == d ) file.push( '\t' );
					else file.push( d );
					continue;
				}
				else if( close_quote == d ) { file.discard; break; }
				else file.push( d );
			}
			return Token( Token.TYPE.STRING, line, file.stack );
		}
		// 1文字でトークンを構成するもの。
		else if( 0 <= ( i=SINGLE_KEYWORD.countUntil(d)) )
		{
			result = Token( Token.TYPE.SINGLE, line, SINGLE_KEYWORD[ i .. i+1 ] );
		}
		// その他のトークン。
		// およその見た目で、整数、浮動小数点数、その他に分類している。
		else
		{
			auto type  = Token.TYPE.NULL;
			void _check_type()
			{
				if     ( Token.TYPE.NULL == type )
				{
					if     ( '0' <=d && d <= '9' ) type = Token.TYPE.INT;
					else if( '.' == d ) type = Token.TYPE.FLOAT;
					else if( '+' == d || '-' == d ){ }
					else type = Token.TYPE.NORMAL;
				}
				else if( Token.TYPE.INT == type )
				{
					if( '.' == d || 'e' == d ) type = Token.TYPE.FLOAT;
				}
			}
			_check_type;

			for( ; ; )
			{
				d = file.front;
				_check_type;
				if( 0 <= TOKEN_STOPPER.countUntil( d ) )
				{
					result = Token( type, line, file.stack );
					break;
				}
				else file.push( d );
			}
		}
		return result;
	}
}

class CTKLispToken : IKLispToken
{
	private string _filename;
	private Token[] _tokens;
	private uint _nest;
	private uint _actual_nest;

	this( string filename, Token[] tokens ){ this._filename = filename; this._tokens = tokens; }

	string filename() @property { return _filename; }
	uint nest() @property { return _nest; }
	uint incNest(){ return ++_nest; }
	uint decNest(){ if( 0 < _nest ) _nest--; return _nest; }
	
	Token nextToken()
	{
		if     ( _actual_nest < _nest ) return Token();
		else if( _nest < _actual_nest )
		{
			incNest;
			for( Token t ; ; )
			{
				t = nextToken();
				if( t.type == Token.TYPE.NULL || t.type == Token.TYPE.EOF ) break;
			}
			decNest;
		}

		Token result;
		if( 0 < _tokens.length )
		{
			result = _tokens[0];
			_tokens = _tokens[ 1 .. $ ];
			if     ( Token.TYPE.OPEN_BRACKET == result.type ) _actual_nest++;
			else if( Token.TYPE.CLOSE_BRACKET == result.type && 0 < _actual_nest ) _actual_nest--;
		}
		return result;
	}

	static string init( alias KF, alias KT )( dstring cont )
	{
		auto kf = new KF( kt );
		auto kt = new KT( kf );
		return initializer( kf.filename, kt );
	}

	static string init( alias KF, alias KT, string filename )()
	{
		auto kf = new KF( import( filename ).to!dstring );
		auto kt = new KT( kf );
		return initializer( filename, kt );
	}

	static string initializer( string filename, IKLispToken kt )
	{
		auto result = appender( "new CTKLispToken(" );
		result.put( "\"" );
		result.put( filename );
		result.put( "\", [" );
		for( Token t ; ; )
		{
			if( Token.TYPE.NULL != t.type ) result.put( ", " );
			t = kt.nextToken;
			result.put( "Token( Token.TYPE." );
			result.put( t.type.to!string );
			result.put( ", " );
			result.put( t.line.to!string );
			result.put( ", \"" );
			result.put( t.value.to!string );
			result.put( "\"d)" );
			if     ( Token.TYPE.OPEN_BRACKET == t.type ) kt.incNest;
			else if( Token.TYPE.CLOSE_BRACKET == t.type ) kt.decNest;
			else if( Token.TYPE.EOF == t.type ) break;
		}
		result.put( "] )" );
		return result.data;
	}
}


debug(token)
{
	import std.conv;
	import sworks.compo.util.output;

	class MyKLispToken : KLispToken
	{
		this( IKLispFile kf ){ super( kf ); }
		Token nextToken()
		{
			if( !adjustNest ) return Token();
			
			enum LINE_COMMENT = ';';

			for( dchar d = file.front ; dchar.init != d ; )
			{
				if( LINE_COMMENT == d )
				{
					for( ; ; )
					{
						d = file.discard;
						if( dchar.init == d || file.newline ) break;
					}
				}
				else if( d.isWhite ) d = file.discard;
				else break;
			}

			return chomp_token!( "\"\"``「」『』"d, "()[]{}［］〔〕【】〈〉＜＞《》';"d );
		}
	}


	void main()
	{
		alias _KLispFile!"()[]{}［］〔〕【】〈〉＜＞《》"d KLispFile;
		try
		{
			auto kf = new KLispFile( "test.kl" );
			auto kt = new MyKLispToken( kf );
			Token t;
			int j;
			for( size_t i = 0 ; i < 10 && !kf.eof ; i )
			{
				t = kt.nextToken;
				Output.ln( j, ", ", to!string(t.type), " : ", t.value );
				if( t.type == Token.TYPE.OPEN_BRACKET ) { j++; kt.incNest; }
				else if( t.type == Token.TYPE.CLOSE_BRACKET ) { j--; kt.decNest; }
			}
		}
		catch( Throwable t )
		{
			Output.ln( t.toString );
		}
	}
}

debug( ct_token )
{
	import std.array, std.conv;
	import sworks.compo.util.output;
	import sworks.klisp.core_kl;

	class MyKLispToken : KLispToken
	{
		this( IKLispFile kf ){ super( kf ); }
		Token nextToken()
		{
			if( !adjustNest ) return Token();
			
			enum LINE_COMMENT = ';';

			for( dchar d = file.front ; dchar.init != d ; )
			{
				if( LINE_COMMENT == d )
				{
					for( ; ; )
					{
						d = file.discard;
						if( dchar.init == d || file.newline ) break;
					}
				}
				else if( d.isWhite ) d = file.discard;
				else break;
			}

			return chomp_token!( "\"\"``「」『』"d, "()[]{}［］〔〕【】〈〉＜＞《》';"d );
		}
	}

	void main()
	{
		try
		{
			auto ckt = mixin( CTKLispToken.init!( KLispFile, MyKLispToken, "test.kl" ) );
			Token t;
			for( ; Token.TYPE.EOF != t.type ;  )
			{
				t = ckt.nextToken;
				Output.ln( ckt.nest, ", ", t.type.to!string, " : ", t.value );
				if( t.type == Token.TYPE.OPEN_BRACKET ) ckt.incNest;
				else if( t.type == Token.TYPE.CLOSE_BRACKET ) ckt.decNest;
				if( t.type == Token.TYPE.NULL ) { Output.ln( "!!!! NULL !!!" ); break; }
			}
		}
		catch( Throwable t ) Output.ln( t.toString );
	}
}