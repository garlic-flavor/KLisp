/** sworks.klisp.klisp_file.IKLispFile 先頭から、1トークンを得る。
 * Version:      0.002(dmd2.060)
 * Date:         2012-Nov-28 15:55:35
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.klisp.token;

import std.ascii, std.exception, std.conv, std.regex, std.string, std.utf, std.algorithm;
import sworks.klisp.klisp_file;

struct Token
{
	enum TYPE { NULL, NORMAL, SINGLE, STRING, INT, FLOAT, OPEN_BRACKET, CLOSE_BRACKET }
	TYPE type;
	const(dchar)[] value;
}

// ユーザ定義パーサ
// 空白文字、コメントなどを取り除く。
alias Token function( IKLispFile cf, int nest_level ) TokenFilter;

/*
 * 次の1トークンを読み込む。
 *
 * Params:
 *   TF = 呼び出し側定義パーサ。空白文字、コメントを取り除く。
 *        これを通した後は、cf 先頭はトークンの1文字目である必要がある。
 *        また、Token.TYPE.NULL 以外の戻り値を返した場合はそれを結果として関数を終える。
 *
 *   QUOTE = 文字列を表現する クォート は dchar 1字で構成され、
 *           開きクォート QUOTE[2n] に対応する閉じクォートは QUOTE[2n+1] であるとする。
 *
 *   SINGLE_KEYWORD = 一字でトークンを構成する。
 *
 *   nest_level = 呼び出し側が期待している 括弧の深度を渡しておくと間違いがない。
 *
 * Return:
 *   戻り値に使われているバッファは再利用される可能性がある。必要なら dup をとる。
 */
Token _nextToken( alias TF // ユーザ定義パーサ
                , dstring QUOTE // 文字列をクォートする。
                , dstring SINGLE_KEYWORD // 1字でトークンを構成する。
                )( IKLispFile cf, int nest_level ) if( is( typeof(&TF) : TokenFilter ) )
{
	// トークンのパース中にこれが表われたらトークンが正しく終了される。
	enum TOKEN_STOPPER = " \r\n\t\0　"d ~ SINGLE_KEYWORD ~ QUOTE;

	// カッコの深度が合わない場合は、
	if     ( cf.nest < nest_level ) return Token();
	for( ; nest_level < cf.nest ; _nextToken!( TF, QUOTE, SINGLE_KEYWORD )( cf, nest_level+1 ) ){ }

	Token result;

	// ユーザ定義フィルタを通す。
	result = TF( cf, nest_level );
	if( Token.TYPE.NULL != result.type ) return result;
	// この段階で cf の先頭は空白文字やコメントではないはずである。

	// 一字切り出し
	int i;
	auto d = cf.chomp;

	// eof
	if( '\0' == d ) return Token();

	// メモのクリア
	cf.flush;

	if     ( DEFAULT_BRACKET[0] == d ) result = Token( Token.TYPE.OPEN_BRACKET );
	else if( DEFAULT_BRACKET[1] == d ) result = Token( Token.TYPE.CLOSE_BRACKET );
	// 文字列
	else if( 0 <= ( i = QUOTE.countUntil(d) ) )
	{
		if( i & 1 ) throw new KLispException( cf.filename, cf.line, [ d ]
			, "トークン中に予期せぬ文字が表われました。"
			  "この文字は閉じクォートとして登録されていますが、現在文字列中ではありません。" );

		assert( i+1 < QUOTE.length );

		auto sl = cf.line;
		auto close_quote = QUOTE[ i + 1 ];
		for( d = cf.peek ; ; d = cf.discard )
		{
			// eof
			if     ( '\0' == d )
			{
				auto buf = QUOTE[ i .. i+1 ] ~ cf.buffer;
				if( 32 < buf.length ) buf = buf[ 0 .. 32 ] ~ " ...";
				throw new KLispException( cf.filename, sl , buf, "文字列に閉じカッコがありません。" );
			}
			// エスケープシーケンス
			else if( '\\' == d )
			{
				d = cf.discard;
				if     ( 'n' == d ) cf.push( '\n' );
				else if( 'r' == d ) cf.push( '\r' );
				else if( 't' == d ) cf.push( '\t' );
				else cf.push( d );
				continue;
			}
			else if( close_quote == d ) { cf.discard; break; }
			else cf.push( d );
		}
		return Token( Token.TYPE.STRING, cf.buffer );
	}
	// 1文字でトークンを構成するもの。
	else if( 0 <= ( i=SINGLE_KEYWORD.countUntil(d)) )
	{
		result = Token( Token.TYPE.SINGLE, SINGLE_KEYWORD[ i .. i+1 ] );
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
		cf.push( d );

		for( d = cf.peek ; ; d = cf.discard )
		{
			_check_type;
			if( 0 <= TOKEN_STOPPER.countUntil( d ) )
			{
				result = Token( type, cf.buffer );
				break;
			}
			else cf.push( d );
		}
	}
	return result;
}

debug(token):

import std.conv;
import sworks.compo.util.output;
import sworks.klisp.core_kl;
void main()
{
	auto cf = new KLispFile( "src/sworks/klisp/yane_kl.d" );
	try
	{
		Token t;
		int j;
		for( size_t i = 0 ; i < 10 && !cf.eof ; i )
		{
			t = cf.token_filter(cf.nest);
			Output.ln( j, ", ", to!string(t.type), " : ", t.value );
			if( t.type == Token.TYPE.OPEN_BRACKET ) j++;
			else if( t.type == Token.TYPE.CLOSE_BRACKET ) j--;
		}
	}
	catch( Throwable t )
	{
		Output.ln( t.toString );
	}

}
