/** YaneLisp 似非互換実装
 * Version:      0.003(dmd2.060)
 * Date:         2013-Jan-14 02:44:54
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.klisp.yane_kl;

// 参照 YaneLisp ( http://labs.yaneu.com/20090905/ )

import std.array, std.ascii, std.conv, std.file, std.string;
import sworks.compo.util.output;
import sworks.klisp.lisp;
import sworks.klisp.token;
import sworks.klisp.klisp_file;

//------------------------------------------------------------------------------
// ファイルパースに関して
enum BRACKET = "()[]{}《》【】〔〕〈〉［］"d;
enum QUOTE = "''\"\"``「」『』"d;
enum SINGLE_KEYWORD = ";:"d ~ BRACKET;

// file 先頭から空白文字とコメントを省く。
// ';' 以降は行末までコメント
// import mode では Lisp の括弧内にあり、行頭が "//%" で始まらない行は連続した文字列であるとする。
class YaneTokenImport : KLispToken
{
	this( IKLispFile kf ){ super( kf ); }

	Token nextToken()
	{
		if( !adjustNest ) return Token();

		for( dchar d ; !file.eof ; )
		{
			d = file.front;

			if( file.newline )
			{
				if     ( "//%"d == file.peek(3) ) file.discard(3);
				else if( 0 == nest )
				{
					for( ; !file.eof ; ) { d = file.discard; if( file.newline ) break; }
				}
				else
				{
					file.flush;
					auto line = file.line;
					for( ; dchar.init != d ; d = file.front )
					{
						if( file.newline && '/' == d && "//%"d == file.peek(3) ) break;
						file.push( d );
					}
					return Token( Token.TYPE.STRING, line, file.stack );
				}
			}
			else
			{
				if     ( ';' == d ) for( ; !file.eof ; ){ d = file.discard; if( file.newline )break; }
				else if( d.isWhite || d == '　' ) file.discard;
				else break;
			}
		}
		return chomp_token!( QUOTE, SINGLE_KEYWORD );
	}
}
//
class YaneTokenInclude : KLispToken
{
	this( IKLispFile kf ){ super( kf ); }
	Token nextToken()
	{
		if( !adjustNest ) return Token();
		for( dchar d ; !file.eof ;  )
		{
			d = file.front;
			if     ( ';' == d ) for( ; !file.eof ; ) { d = file.discard; if( file.newline ) break; }
			else if( d.isWhite || d == '　' ) file.discard;
			else break;
		}
		return chomp_token!( QUOTE, SINGLE_KEYWORD );
	}
}

alias _KLispFile!( BRACKET ) YaneFile;

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// 追加の基本型

//------------------------------------------------------------------------------
// Undef から派生しない方がうまくいくようだ。
class Null : AddressPart
{
	override dstring toDstring() @property { return "#null"; }
}

//------------------------------------------------------------------------------
//
class True : AddressPart
{
	override bool toBool() @property { return true; }
	override int toInt() @property { return 1; }
	override double toDouble() @property { return 1.0; }
	override dstring toDstring() @property { return "#true"; }
}

//------------------------------------------------------------------------------
//
class False : AddressPart
{
	override dstring toDstring() @property { return "#false"; }
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// 出力関係

//------------------------------------------------------------------------------
// 標準出力
class OutExp : FuncBase
{
	this() { super( "out" ); }
	override SExp eval( EvalInfo ei )
	{
		auto data = ei.evalAll.toDstringAll;
		Output.ln( data );
		return S!Dstr( data );
	}
}

//------------------------------------------------------------------------------
// 評価せずに標準出力
SExp print( EvalInfo ei )
{
	Appender!dstring buf;
	void _print( SExp one )
	{
		for( ; !one.empty ; one.popFront )
		{
			if     ( one.isTypeOf!List )
			{
				buf.put( "(" );
				_print( one.car );
				buf.put( ")" );
			}
			else if( one.isTypeOf!Symbol )
			{
				buf.put( one.toDstring );
			}
			else buf.put( "'"d ~ one.toDstring ~ "'"d );

			if( one.remain ) buf.put( " " );
		}
	}

	for( SExp ite ; ei.remain ; )
	{
		ite = ei.rest.popFront;
		if( ite.isTypeOf!Symbol ) _print( ite.car );
		else _print( ei.evalAllChild( ite ) );

		if( !ei.rest.empty ) buf.put( " " );
	}
	
	return S!Dstr( buf.data );
}

//------------------------------------------------------------------------------
// ファイル出力。
// ファイル名として 'outfile' という名前のシンボルにアクセスする。
class WriteExp : FuncBase
{
	this(){ super( "write" ); }

	override SExp filter( SymbolScope parent_ss, Parser parser )
	{
		return SExp( new FuncBody( parent_ss[ "", 0, "outfile"] ) );
	}

	class FuncBody : AddressPart
	{
		SExp outfile;
		this( SExp outfile ) { this.outfile = outfile; }

		SExp eval( EvalInfo ei )
		{
			auto filename = outfile.car.toDstring.to!string;
			auto data = ei.evalAll.toDstringAll;
			if( filename.exists ) filename.append( data.to!string );
			else filename.write( data.to!string );

			return S!Dstr( data );
		}
	}
}

//------------------------------------------------------------------------------
// ファイルを消去する。
SExp del( EvalInfo ei )
{
	auto filename = ei.popEval.toDstring.to!string;
	if( filename.exists ) std.file.remove( filename );
	ei.rest.clear;
	return SExp();
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// リスト操作関係

//------------------------------------------------------------------------------
// 評価した値を取り出す
SExp get( EvalInfo ei )
{
	Appender!dstring result;
	for( auto arg = ei.evalAll ; !arg.empty ; arg.popFront )
	{
		if( null is cast(Null)arg.address ) result.put( arg.toDstring );
	}

	return S!Dstr( result.data );
}

//------------------------------------------------------------------------------
// 引数を評価してからシンボルに追加
SExp set( EvalInfo ei )
{
	auto target = ei.rest.popFront;
	auto val = ei.evalAll;
	target.car = val;

	return S!Dstr( val.toDstringAll );
}

//------------------------------------------------------------------------------
// 引数を評価せずにシンボルに追加
SExp let( EvalInfo ei )
{
	auto target = ei.rest.popFront;
	auto val = ei.rest;
	target.car = val.dupAll;
	ei.rest.clear;
	return val.dupAll;
}

//------------------------------------------------------------------------------
//
SExp car( EvalInfo ei )
{
	auto sexp = ei.rest.popFront;
	if( sexp.isTypeOf!Symbol ) sexp = sexp.car;
	ei.rest.clear;
	return SExp(sexp.car);
}

//------------------------------------------------------------------------------
//
SExp cdr( EvalInfo ei )
{
	auto sexp = ei.rest;
	if( sexp.isTypeOf!Symbol ) sexp = sexp.car;
	sexp.popFront;
	ei.rest.clear;
	return sexp.empty ? S!Null : sexp;
}

//------------------------------------------------------------------------------
//
/* あってもなくても一緒
class Eval : FuncBase
{
	this(){ super( "eval" ); }

	SExp eval( EvalInfo ei ){ return SExp(); }
}
*/

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// ループ

//------------------------------------------------------------------------------
//
class ForEachExp : FuncBase
{
	this( ) { super( "foreach" ); }

	override SExp filter( SymbolScope parent_ss, Parser parser )
	{
		auto symbol_scope = new SymbolScope;
		auto one_symbol = parser( symbol_scope );
		if( !one_symbol.isTypeOf!Symbol )
			throw new KLispMessage( "foreach 関数の第一引数はシンボル名である必要があります。" );

		auto list = parser( parent_ss );
		symbol_scope.parent = parent_ss;
		auto func_body = parser( symbol_scope );

		return SExp( new FuncBody( one_symbol, list, func_body ) );
	}

	override SExp eval( EvalInfo ei ) { return SExp(); }

	class FuncBody : AddressPart
	{
		SExp one;
		SExp list;
		SExp func;
		this( SExp o, SExp l, SExp func ) { this.one = o; this.list = l; this.func = func; }
		override SExp eval( EvalInfo ei )
		{
			Appender!dstring result;
			for( auto ite = list.car ; !ite.empty && !ei.breaking ; ite.popFront )
			{
				one.car = SExp( ite.address );
				auto r = ei.evalAllChild( func );
				if( !r.empty ) result.put( r.toDstring );
			}
			ei.rest.clear;
			return S!Dstr( result.data );
		}
	}
}

//------------------------------------------------------------------------------
//
SExp loop( EvalInfo ei )
{
	auto times = ei.popEval.toInt;
	auto func_body = ei.rest;
	SExp r;
	for( int i = 0 ; i < times && !ei.breaking ; i++ ) r = ei.evalAllChild( func_body );
	ei.rest.clear;
	return r;
}

//------------------------------------------------------------------------------
//
class WhileExp : FuncBase
{
	this(){ super( "while" ); }
	override SExp eval( EvalInfo ei )
	{
		auto exp = ei.rest.popFront.car;
		auto prog = ei.rest.popFront.car;
		ei.rest.clear;
		SExp r;
		while( !ei.breaking && ei.evalAllChild( exp ).toBool ) r = ei.evalAllChild( prog );
		return r;
	}
}

//------------------------------------------------------------------------------
//
class ForExp : FuncBase
{
	this(){ super( "for" ); }
	override SExp filter( SymbolScope parent_ss, Parser parser )
	{
		auto ss = new SymbolScope;
		auto counter = parser( ss );
		if( !counter.isTypeOf!Symbol )
			throw new KLispMessage( "for 関数の第一引数にはループカウンタ用のシンボルを渡して下さい。" );
		auto start = parser(parent_ss);
		auto end = parser(parent_ss);
		ss.parent = parent_ss;
		auto prog = parser(ss);
		return SExp( new FuncBody( counter, start, end, prog ) );
	}

	class FuncBody : AddressPart
	{
		SExp counter;
		SExp start, end, prog;
		this( SExp counter, SExp start, SExp end, SExp prog )
		{
			this.counter = counter;
			this.start = start; this.end = end; this.prog = prog;
		}
		override SExp eval( EvalInfo ei )
		{
			auto i = ei.evalAllChild( start ).toInt;
			auto end_count = ei.evalAllChild( end ).toInt;
			auto ic = new Int( i );
			counter.car = SExp( ic );
			SExp r;
			for( ; !ei.breaking && i <= end_count ; i++ )
			{
				ic.value = i;
				r = ei.evalAllChild( prog );
			}
			return r;
		}
	}
}

//------------------------------------------------------------------------------
class DownForExp : FuncBase
{
	this(){ super( "downfor" ); }
	override SExp filter( SymbolScope parent_ss, Parser parser )
	{
		auto ss = new SymbolScope;
		auto counter = parser( ss );
		if( !counter.isTypeOf!Symbol )
			throw new KLispMessage( "for 関数の第一引数にはループカウンタ用のシンボルを渡して下さい。" );
		auto start = parser(parent_ss);
		auto end = parser(parent_ss);
		ss.parent = parent_ss;
		auto prog = parser(ss);
		return SExp( new FuncBody( counter, start, end, prog ) );
	}

	class FuncBody : AddressPart
	{
		SExp counter;
		SExp start, end, prog;
		this( SExp counter, SExp start, SExp end, SExp prog )
		{
			this.counter = counter;
			this.start = start; this.end = end; this.prog = prog;
		}

		override SExp eval( EvalInfo ei )
		{
			auto i = ei.evalAllChild( start ).toInt;
			auto end_count = ei.evalAllChild( end ).toInt;
			SExp r;
			auto ic = new Int( i );
			counter.car = SExp( ic );
			for( ; !ei.breaking && end_count <= i ; i-- )
			{
				ic.value = i;
				r = ei.evalAllChild( prog );
			}
			return r;
		}
	}
}

//------------------------------------------------------------------------------
SExp forever( EvalInfo ei )
{
	SExp result, r;
	for( ; !ei.breaking ; )
	{
		r = ei.evalAllChild( ei.rest );
		if( !r.empty ) result = r;
	}
	return result;
}

//------------------------------------------------------------------------------
// シンボルが確保されている SymbolScope までスコープを抜ける。
// (label: break label)
//   │  |
//   │  └ 関数 ':'         ┐
//   └── シンボル 'label' ┴ この二つは別もん。
// 関数 ':' 自身の引数のパース時に新しい SymbolScope を導入する。
// 実行が、EvalInfo.breaking == true で終わってきた時、自身が新規導入したスコープの親スコープに break で指定されたシンボル名が確保されてたら EvalInfo.recover する。
class BreakScope : FuncBase
{
	enum KEYWORD = "break_keyword"d;

	this(){ super( ":" ); }

	override SExp filter( SymbolScope parent_ss, Parser parser )
	{
		auto ss = new SymbolScope( parent_ss );
		SExpAppender acc;
		for( ; acc.put( parser(ss) ) ; ) { }
		return SExp( new FuncBody( parent_ss, acc.data ) );
	}

	override SExp eval( EvalInfo ei ){ return SExp(); }

	class FuncBody : AddressPart
	{
		SymbolScope _parent_ss;
		SExp _body;
		this( SymbolScope parent_ss, SExp _body )
		{
			this._parent_ss = parent_ss;
			this._body = _body;
		}

		override SExp eval( EvalInfo ei )
		{
			auto result = ei.evalAllChild( _body );
			if( ei.breaking )
			{
				SExp* p = KEYWORD in ei.info;
				if( null is p || _parent_ss.have( p.toDstring ) ) ei.recover;
			}
			return result;
		}
	}
}

//------------------------------------------------------------------------------
class Break : FuncBase
{
	this(){ super( "break" ); }

	override SExp eval( EvalInfo ei )
	{
		if( ei.remain )
		{
			if( ei.rest.isTypeOf!Symbol ) ei.info[BreakScope.KEYWORD] = ei.rest.popFront;
			else ei.info[BreakScope.KEYWORD] = ei.popEval;
		}
		ei.breakOut;
		return SExp();
	}
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// 分岐

//------------------------------------------------------------------------------
class IfExp : FuncBase
{
	this(){ super( "if" ); }

	override SExp eval( EvalInfo ei )
	{
		auto exp = ei.popEval;
		SExp result;
		if     ( exp.empty ) { }
		else if( exp.toBool ) result = ei.popEval;
		else { ei.rest.popFront; result = ei.popEval; }
		if( result.empty ) result = S!False;
		ei.rest.clear;
		return result;
	}
}

//------------------------------------------------------------------------------
SExp or( EvalInfo ei )
{
	for( ; ei.remain ; )
	{
		if( ei.popEval.isTypeOf!True )
		{
			ei.rest.clear;
			return S!True;
		}
	}
	return S!False;
}

//------------------------------------------------------------------------------
SExp and( EvalInfo ei )
{
	for( ; ei.remain ; )
	{
		if( !ei.popEval.isTypeOf!True )
		{
			ei.rest.clear;
			return S!False;
		}
	}
	return S!True;
}

//------------------------------------------------------------------------------
class Switch : FuncBase
{
	this(){ super( "switch" ); }
	override SExp eval( EvalInfo ei )
	{
		auto s = ei.popEval;
		SExp result, ite;
		dstring c;
		for( ; ei.remain ; )
		{
			ite = ei.rest.popFront.car;
			if( ite.isTypeOf!Symbol && "default"d == ite.toDstring )
			{
				result = ei.evalAllChild( ite );
				break;
			}
			else
			{
				c = ei.evalAllChild( ite.popFront ).toDstring;
				if( s.toDstring == c && !ite.empty)
				{
					result = ei.evalAllChild( ite );
					break;
				}
			}
		}
		ei.rest.clear;
		return result;
	}
}


//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// 数値関係

//------------------------------------------------------------------------------
SExp math_op( string OP )( EvalInfo ei )
{
	auto arg = ei.evalAll;
	auto value = arg.popFront.toDouble;
	for( ; !arg.empty ; arg.popFront ) mixin( "value " ~ OP ~ "= arg.toDouble;" );

	return S!Double( value );
}
alias math_op!"+" add;
alias math_op!"-" sub;
alias math_op!"*" mul;
alias math_op!"/" div;

//------------------------------------------------------------------------------
//
SExp compExp(string OP)( EvalInfo ei )
{
	auto a = ei.popEval.toDouble;
	for( ; ei.remain ; )
	{
		auto b = ei.popEval.toDouble;
		if( !(mixin( "a " ~ OP ~ " b" )) ) return S!False;
		a = b;
	}
	return S!True;
}
alias compExp!"<" lt;
alias compExp!">" gt;
alias compExp!">=" ge;
alias compExp!"<=" le;



//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// 配列関係

//------------------------------------------------------------------------------
SExp array( EvalInfo ei )
{
	SExp array;
	if( ei.rest.isTypeOf!Symbol )
	{
		array = ei.rest.popFront.car;
		if( !array.remain && array.isTypeOf!List ) array = array.car;
	}
	else array = ei.popEval;
	if( array.empty ) return SExp();

	auto pos = ei.popEval.toInt;
	for( int i = 0 ; i < pos && array.remain ; i++, array.popFront ){ }
	ei.rest.clear;
	return array.car;
}

//------------------------------------------------------------------------------
SExp setarray( EvalInfo ei )
{
	SExp target = ei.rest;
	SExp array;
	if( target.isTypeOf!Symbol )
	{
		array = ei.rest.popFront.car;
		if( !array.remain && array.isTypeOf!List ) array = array.car;
	}
	else array = ei.popEval;
	if( array.empty ) return SExp();
	if( array.isTypeOf!Undef ) array.popFront;

	auto r = ei.popEval;
	if( r.empty ) return SExp();
	auto pos = r.toInt;

	auto arg = ei.popEval;
	if( arg.empty ) return SExp();

	SExpAppender acc;
	Appender!dstring buf;
	SExp ite;

	for( size_t i = 0 ; i <= pos || !array.empty ; i++, ite.clear )
	{
		if     ( i == pos ) { ite = arg; array.popFront; }
		else if( !array.empty )
		{
			ite = array.popFront;
			ite.cdr = null;
		}
		else ite = S!Null();

		acc.put( ite );
		buf.put( ite.toDstring );
	}

	target.car = acc.data;
	ei.rest.clear;
	return S!Dstr( buf.data );
}

//------------------------------------------------------------------------------
SExp length( EvalInfo ei )
{
	SExp array;
	if( ei.rest.isTypeOf!Symbol )
	{
		array = ei.rest.popFront.car;
		if( !array.remain && array.isTypeOf!List ) array = array.car;
	}
	else array = ei.evalAll;
	ei.rest.clear;
	int i = 0;
	for( ; !array.empty ; array.popFront ) i++;
	return S!Int( i );
}


//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// 文字列関係

//------------------------------------------------------------------------------
// 文字列を追加
SExp addto( EvalInfo ei )
{
	auto target = ei.rest;
	auto param = ei.evalAll;
	if( param.isTypeOf!Undef ) param.popFront;

	auto r = S!Dstr( param.toDstringAll );
	target.car = r;
	return r;
}


//------------------------------------------------------------------------------
// 文字の置換
SExp replace( EvalInfo ei )
{
	auto _subject = ei.popEval;
	if( _subject.empty ) return SExp();
	auto _from = ei.popEval;
	if( _from.empty ) return SExp();
	auto _to = ei.popEval;

	auto sub_str = _subject.toDstring;
	auto from_str = _from.toDstring;
	auto to_str = _to.empty ? "" : _to.toDstring;
	auto result = std.array.replace( sub_str, from_str, to_str );
	ei.rest.clear;
	return S!Dstr( result );
}

//------------------------------------------------------------------------------
//
SExp toXXXXX(alias FUNC)( EvalInfo ei )
{
	auto symbol = ei.rest.popFront;
	if( symbol.empty ) return SExp();
	symbol.car = S!Dstr( FUNC(ei.evalAll.toDstringAll) );
	return symbol.car;
}
alias toXXXXX!toLower tolower;
alias toXXXXX!(std.string.toUpper) toupper; // ?

//------------------------------------------------------------------------------
SExp eq( EvalInfo ei )
{
	auto a = ei.popEval;
	auto b = ei.popEval;
	ei.rest.clear;
	return a.toDstring == b.toDstring ? S!True : S!False;
}

//------------------------------------------------------------------------------
SExp neq( EvalInfo ei )
{
	auto a = ei.popEval;
	auto b = ei.popEval;
	ei.rest.clear;
	return a.toDstring != b.toDstring ? S!True : S!False;
}


//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// 関数定義

//------------------------------------------------------------------------------
// ※ YaneLisp と若干異なります。
// ローカル変数は、@0 〜 @9 までしか使えません。
// @params に引数全てのリストが入っています。
class Defun : FuncBase
{
	this() { super( "func" ); }

	override SExp filter( SymbolScope parent_ss, Parser parser )
	{
		auto ss = new SymbolScope( parent_ss );
		ss.local( "@params"d, S!Undef );
		for( size_t i = 0 ; i < 10 ; i++ ) ss.local( "@"d ~ i.to!dstring, S!Undef );
		auto func_symbol = cast(Symbol)parser( parent_ss ).address;
		if( null is func_symbol )
			throw new KLispMessage( " func 関数の第一引数は関数名を格納するシンボル名である必要があります。" );
		auto func_body = parser( ss );
		func_symbol.contents = SExp( new FuncBody( func_symbol, ss, func_body ) );
		return SExp();
	}
	override SExp eval( EvalInfo ei ){ ei.rest.clear; return SExp(); }

	class FuncBody : AddressPart
	{
		dstring name;
		string filename;
		size_t line;
		SymbolScope ss;
		SExp _body;
		SExp _params;
		SExp[10] _arg;
		this( Symbol symbol, SymbolScope ss, SExp func_body )
		{
			this.name = symbol.name;
			this.filename = symbol.filename;
			this.line = symbol.line;
			this.ss = ss;
			this._body = func_body;
			_params = ss[ filename, line, "@params" ];
			for( size_t i = 0 ; i < 10 ; i++ ) _arg[i] = ss[ filename, line, "@"d ~ i.to!dstring ];
		}

		override SExp eval( EvalInfo ei )
		{
			SExpAppender acc;
			SExp p, ite;

			for( size_t i = 0 ; i < _arg.length ; i++ )
			{
				ite = ei.rest.popFront;
				if( ite.isTypeOf!Symbol ) p = ite.car;
				else p = ei.evalAllChildResult( ite );
				_arg[i].car = p;
				acc.put( p.dupAll );
			}
			_params.car = acc.data;
			return ei.evalAllChild( _body );
		}
	}
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// インポート
class _includeExp(alias TOKEN, dstring NAME ) : FuncBase
{
	this(){ super( NAME ); }
	override SExp filter( SymbolScope parent_ss, Parser parser )
	{
		auto filename = parser( parent_ss ).toDstring.to!string;
		auto yf = new YaneFile( filename );
		auto yt = new TOKEN( yf );
		SExpAppender acc;
		for( ; acc.put( sworks.klisp.lisp.parse( yt, parent_ss ) ) ; ){ }
		return acc.data;
	}

	override SExp eval( EvalInfo ei )
	{
		auto result = ei.evalAllChild( ei.rest );
		ei.rest.clear;
		return result;
	}
}
alias _includeExp!( YaneTokenInclude, "include" ) IncludeExp;
alias _includeExp!( YaneTokenImport, "import" ) ImportExp;

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// ユニットテスト
void assertEval( dstring code, dstring value, string file = __FILE__, int line = __LINE__ )
{
	auto ss = new SymbolScope;
	ss.entry!( sworks.klisp.yane_kl );
	auto yf = new YaneFile( code );
	auto yt = new YaneTokenInclude( yf );
	auto result = yt.eval( ss ).toDstringAll;
	if( result != value ) throw new Exception( (result ~ " != " ~ value).to!string, file, line );
}

unittest
{
        Output.ln( " ************* unittest 開始 *************" );
	try
	{
        // 文字列とは
        // quoteされたもの(ダブルコーテイションで囲われたもの or シングルクォートで囲まれたもの、
        // あと、「」『』で囲まれたもの。ソースはutf-16にて記述する。)
        // 数値、記号(+,-,*,/)で始まるもの
        // それ以外は変数名・関数名。変数名と関数名との区別は無い。

        // 数値の加算
        // 返し値は文字列として扱われる。また加算のときに文字列は強制的に数値に変換される。

        assertEval("(add 1 2 3 4 5 6 7 8 9 10)", "55");

        assertEval("(add '1' '2' '3' '4' '5' '6' '7' '8' '9' '10')", "55");

        // 小数も使える。
        assertEval("(add 1.5 2.7)", "4.2");

        // 負数も使える。
        assertEval("(add 3 -5)", "-2");

        // 数値の減算。10-2-3 = 5
        assertEval("(sub 10 2 3)", "5");

        // 数値の掛け算。2*3*4 = 24
        assertEval("(mul 2 3 4)", "24");

        // 数値の割り算。10/2/2 = 2.5
        assertEval("(div 10 2 2)", "2.5");

        // 内部的には、数値は演算するまでは文字列として扱われる。
        // また演算はすべてC#のdouble型(倍精度浮動小数)で行なわれる。

        // 文字列の連結。
        // addしたものは文字列である。
        // getは文字列を連結するので次のような結果になる。
        assertEval("(get 1 2 3 4 5 (add 6 7) 8 9 10)", "12345138910");

        // '' "" 「」 『』で囲まれたものは文字列
        assertEval("(get 「日本語」'も'『使えるよ』)", "日本語も使えるよ");

        // 日本語の変数名も使える
        assertEval("(set 歩の価値 250)(get 歩の価値)", "250");

        // 未定義の変数を表示させようとした場合、#undefが返る
        assertEval("(get x)", "#undef");

        // printは変数も保持している内容を再度conv2SExpで変換して、eval可能な文字列にする。
        // S式のシリアライズみたいなもの。
        // 定義されていない変数に対してはundefになる。
        // xを評価しようとする→#undefが返る → printはそれを忠実に表示するために、
        // #undefは文字列なので文字列化するためにコーテイションで囲って返す
        assertEval("(print x)", "'#undef'");

        // 書式 ( let 変数名 代入する文字列 )
        // letは、変数名を指定して、文字列 or S式の内容を格納する。
        // ' ' か " "で囲まれていればそれは文字列。
        // 代入する側にある変数名は一切評価されない。
        // 本家LISPの '(...) という表記に対応する。
        assertEval("(let x 'AAA')(print x)", "'AAA'");
        assertEval("(let x 'AAA' 'BBB')(print x)", "'AAA' 'BBB'");

        // letは中身を評価せずにそのまま格納して、printも中身を評価せずにそのまま表示。
        // よって、次のようになる。
        assertEval("(let x 'AAA' (cat 'BBB' 'CCC'))(print x)", "'AAA' (cat 'BBB' 'CCC')");
        assertEval("(let x 'AAA') (let y 'BBB' 'CCC') (print x y)", "'AAA' 'BBB' 'CCC'");

        // (get 変数名1 変数名2 …)
        // getは変数名1,2,…を評価して、それを式の値にする。
        // 文字列は、'…'として格納している。

        // getは評価したときに要素と要素との間にスペースは入らない。
        assertEval("(let x 'AAA' 'BBB')(get x)", "AAABBB");
        assertEval("(let x 'AAA')(let y 'BBB')(get x y)", "AAABBB");
        assertEval("(let x 'AAA' 'BBB' 'CCC')(get x)", "AAABBBCCC");

        // printとgetとの違い。
        // letは中身を評価せずにそのまま持っている。printはだからそのまま表示する。
        // これをgetで表示しようとしたとき、getは変数の中身をそれぞれ評価しながら表示する。
        // よって動作は以下のような違いが生じる。
        assertEval("(let x 'AAA' 'BBB' (get 'CCC' 'DDD'))(print x)", "'AAA' 'BBB' (get 'CCC' 'DDD')");
        assertEval("(let x 'AAA' 'BBB' (get 'CCC' 'DDD'))(get x)", "AAABBBCCCDDD");
        assertEval("(let y 'EEE')(let x 'AAA' 'BBB' (get 'CCC' 'DDD' y))(get x)", "AAABBBCCCDDDEEE");
        assertEval("(let y 'EEE')(let x 'AAA' 'BBB' (get 'CCC' 'DDD') y)(get x)", "AAABBBCCCDDDEEE");

        // getは出現した変数はすべて再帰的に評価される。(循環参照に注意！)
        assertEval("(let x 'AAA')(let y x)(get y)", "AAA");

        // setはletと違い、代入のときに変数名はすべて評価される。
        assertEval("(let x 'AAA')(set y 'BBB')(let z x y)(print z)", "x y");
        assertEval("(let x 'AAA')(set y 'BBB')(let z x y)(get z)", "AAABBB");
        assertEval("(set x 'AAA' 'BBB')(get x)", "AAABBB");
        assertEval("(let z 'DDD')(set x 'AAA' 'BBB' 'CCC' z)(let y x)(get y)", "AAABBBCCCDDD");
        assertEval("(let z 'DDD')(set x 'AAA' (get 'BBB' 'CCC'))(set y x)(get y)", "AAABBBCCC");

        // addtoは文字列を変数に追加
        assertEval("(addto x 'AAA')(addto x 'BBB')(get x)", "AAABBB");

        // 書式 ( foreach 変数名 コレクション名 (実行する式) )
        // foreachはコレクションをひとつずつ変数に代入しながら、
        // 後続する命令を実行する。
        // 複数実行するなら、さらに括弧でくくること。
        // 例 : foreach x xs ( (command1) (command2) … )
        // また、foreachの値は、評価した式を連結したものになる。
        assertEval("(set xs 'AAA' 'BBB' 'CCC' ) (foreach x xs (get x))","AAABBBCCC");

        // replaceは文字置換した値を返す
        assertEval("(set xs 'AAA' 'BBB' 'CCC' ) (foreach x xs (get (replace '123xxx456xxx' 'xxx' x) ' '))",
           "123AAA456AAA 123BBB456BBB 123CCC456CCC ");

        // ファイル or 標準出力にoutする。
        //**/  assertEval("(out 'AAA' 'BBB' 'CCC' )","AAABBBCCC");

        // write という、ファイルに出力する命令を用意する。
        // writeは'outfile'という変数に格納されているファイル名のファイルに出力する。
        //**/ assertEval( "(set outfile 'test.log') (write 'ABCDEF')", "ABCDEF" ); // とやれば、
        // test.logに'ABCDEF'が出力される。

        // 2重のforeach
        assertEval("(let list 'x_A' 'x_B' 'x_C')(let list2 'y_A' 'y_B' 'y_C')(foreach e list(foreach e2 list2 (replace (replace 'XXXYYY' 'XXX' e2) 'YYY' e) ))", "y_Ax_Ay_Bx_Ay_Cx_Ay_Ax_By_Bx_By_Cx_By_Ax_Cy_Bx_Cy_Cx_C");

        // 未定義の変数をsetした場合、それをsetした瞬間に評価され、結果は#undefになる。
        assertEval("(set list x_A x_B x_C)", "#undef#undef#undef");

        // これは無限再帰で、再帰が深いので、エラーになる。
        //**/  assertEval("(let x y)(let y x)(get y)", "x");

        // これは、set y x のときに、xの定義を参照しに行き、そこでyが使われているが、
        // yはまだsetが完了していないので未定義であり、結局、yにはこの未定義であるy(#undef)が
        // 代入される。
        assertEval("(let x y)(set y x)", "#undef");

        // loopは繰り返す…が、最後に評価されたものが式の値になるので結果は最後に評価された式になる。
        assertEval("(loop 3 (get 'ABC'))", "ABC");
        assertEval("(loop 3 (get 'ABC')(get 'DEF'))", "DEF");

        // 回数は3×5回で15になっているので、きちんとループで実行されていることがわかる。
        assertEval("(set sum 0)(loop 5 {set sum (add sum 3)})", "15");

        // loopの回数を指定するところには、変数も指定できる。変数の値は変化しない。
        assertEval("(set total 7)(set sum 0)(loop total (set sum (add sum 3)))", "21");

        // tolower/toupperは小文字化する
        assertEval("(set x 'Abc')(set y 'deF')(tolower z x y)(get z)", "abcdef");
        assertEval("(set x 'Abc')(set y 'deF')(toupper z x y)(get z)", "ABCDEF");

        // arrayによって配列とみなして任意の要素を取り出せる
        assertEval("(set x 'AAA' 'BBB' 'CCC')(set y (array x 2))(get y)", "CCC");

        // arrayによって、配列の配列からも任意の要素を取り出せる。
        assertEval("(let x ('AAA' 'BBB')('CCC' 'DDD') )(set y (array (array x 1) 1))(get y)", "DDD");

        // 配列の配列に対するforeachとarrayとの組み合わせ
        assertEval("(let x ('AAA' 'BBB')('CCC' 'DDD') ) (foreach e x (get (array e 1)) )", "BBBDDD");

        // 配列の配列に対するforeachとarrayによるreplaceの繰り返し
        assertEval("(let x ('AAA' 'XXX')('BBB' 'YYY')('CCC' 'ZZZ') )(set z 'AAAWWWBBBWWWCCC') (foreach e x (set z (replace z (array e 0) (array e 1) ) )) (get z)"
          , "XXXWWWYYYWWWZZZ");

        // arrayとみなして任意の位置の要素を設定できる。
        // これは高速化のために参照透明性を壊すので、他のオブジェクトから参照されているとそちらも更新されてしまうので注意すること。
        assertEval("(set x 'AAA' 'BBB' 'CCC')(setarray x 2 'DDD')(get x)", "AAABBBDDD");

        // 配列の任意の位置に設定できる。サイズを超えた場合は配列は自動的に拡張される。
        // 拡張された部分はすべて #null になる。
        assertEval("(setarray x 10 'DDD')(setarray x 3 'CCC')(get x)", "CCCDDD");
        assertEval("(setarray x 10 'DDD')(setarray x 3 'CCC')(array x 3)", "CCC");
        assertEval("(setarray x 10 'DDD')(setarray x 3 'CCC')(array x 2)", "#null");


        // 配列の大きさはlengthによって取得できる。
        assertEval("(let x 'AAA' 'BBB' 'CCC')(length x)", "3");
        assertEval("(setarray x 10 'DDD')(setarray x 3 'CCC')(length x)", "11");

        // eqは中身を評価して文字列レベルでの一致を調べる。
        // 一致すれば#true , 一致しなければ #falseが返る。
        // neqはeqと逆条件。not equalの略
        assertEval("(eq 'ABC' 'ABC')", "#true");
        assertEval("(eq 'ABC' 'CDE')", "#false");
        assertEval("(set x 'ABC')(eq x 'ABC')", "#true");
        assertEval("(set x 'ABC')(eq x 'CDE')", "#false");
        assertEval("(set x 'CDE')(neq x 'CDE')", "#false");
        assertEval("(set x 'ABC')(neq x 'CDE')", "#true");

        // ifは#trueならば直後の式を評価する。さもなくば、その次の式を評価する。
        // そして評価した式を副作用として返す
        assertEval("(set x 'AAA')(if (eq x 'AAA') 'TRUE' 'FALSE')", "TRUE");
        assertEval("(set x 'AAA')(if (neq x 'AAA') 'TRUE' 'FALSE')", "FALSE");
        assertEval("(set x 'AAA')(if (eq x 'AAA') (set x 'BBB') (set x 'CCC'))(get x)", "BBB");

        // ifの式が偽で、else相当句がなければ、if式の値として#falseが返る。
        assertEval("(set x 'AAA')(if (eq x 'BBB') 'TRUE')", "#false");

        // ifは3項演算子と等価。
        assertEval("(set x 5)(set y (if (eq x 5) 1 2))(get y)", "1");
        assertEval("(set x 3)(set y (if (eq x 5) 1 2))(get y)", "2");

        // or演算子はどちらかが#trueならば#true
        assertEval("(or 'AAA' (eq 1 1))", "#true");
        // and演算子は両方が#trueのときだけ#true
        assertEval("(and 'AAA' (eq 1 1))", "#false");
        assertEval("(and (eq 5 5)(eq 3 3) )", "#true");

        // whileは条件式が #true の間、回り続ける
        // (while cond exp)
        // 5回ループでyに毎回3ずつ足せば合計は15になっているはず。
        assertEval("(set x 0)(set y 0)(while (neq x 5) ((set x (add x 1)) (set y (add y 3))))(get y)", "15");

        // forで回すことが出来る。
        // for ループカウンタ 開始値 終了値 評価する式
        // ダウンカウントはしない。
        assertEval("(set z '')(for x 0 9 (addto z x) ) (get z)", "0123456789");

        // ループカウンタが1ずつ減るfor
        assertEval("(set z '')(downfor x 9 0 (set z (get z x)) ) (get z)", "9876543210");


        // 大小比較
        // gt = greater than : < , lt = less than : >
        // ge = greater equal : <= , le = less or equal : <=
        assertEval("(lt 1 2)", "#true");
        assertEval("(lt 2 1)", "#false");
        assertEval("(lt 1 1)", "#false");
        assertEval("(gt 1 2)", "#false");
        assertEval("(gt 2 1)", "#true");
        assertEval("(gt 1 1)", "#false");
        assertEval("(ge 1 2)", "#false");
        assertEval("(ge 2 1)", "#true");
        assertEval("(ge 1 1)", "#true");
        assertEval("(le 1 2)", "#true");
        assertEval("(le 2 1)", "#false");
        assertEval("(le 1 1)", "#true");

        // car,cdr。これはLISPのものに準拠する。
        assertEval("(let x 1 2 3)(car x)", "1");
        assertEval("(let x 1 2 3)(cdr x)", "23");
        assertEval("(let x 1)(cdr x)", "#null");
        assertEval("(let x 1 2 3)(print (cdr x))", "'2' '3'");

        // evalは変数に代入された式を評価する。
        assertEval("(let x (print 'ABC'))(eval x)", "'ABC'");
        assertEval("(let x (set y 'ABC')(addto y 'DEF'))(eval x)", "ABCDEF");
        assertEval("(set x 3)(let z (add x 4))(set y (if (eq x 5) 1 (eval z)))(get y)", "7");

        // 括弧として (){}[]《》【】〔〕〈〉［］が使える。同じ種類の括弧が対応している必要がある。
        // すべて () と等価。
        assertEval("(set y {add 1 2}) (let x {print 'ABC' y})[eval x]", "'ABC' '3'");

        // func命令は関数を定義する。これだけなら、evalしているのと変わらない。
        assertEval("(func F (print 'ABC')) (F)", "'ABC'");

        // @で始まるのはローカル変数。関数のなかでだけ使える。
        // また、特に、@0,@1,…は関数に渡されたパラメータ。
        assertEval("(func F (get @0 'と' @1)) (F 'ABC' 'DEF')", "ABCとDEF");
        assertEval("(func F [get @0 'と' @1]) (let p1 'ABC' 'DEF') (let p2 'GHI') (F p1 p2)", "ABCDEFとGHI");
        assertEval("(func F [print @0 'と' @1]) (let p1 ('ABC' 'DEF'))(let p2 'GHI') (F p1 p2)", "('ABC' 'DEF') 'と' 'GHI'");

        // ':'で終わる変数名に見えるものはラベル。変数名と':'との間にスペースなどを入れるのは不可。
        // break + ラベルでそのlabelのステートメントを抜ける。(JavaScript風)
        assertEval("(label1: while '#true' { (print 'ABC')(break label1) } ) ", "'ABC'");

        // break + ラベルでいくつでも外のスコープまで抜けることが出来る。さながら例外処理である。
        assertEval("(label0: while '#true' { label1: while '#true' { (print 'ABC')(break label0) }} ) ", "'ABC'");

        // forなど制御構文もbreakで抜けることが出来る。
        assertEval("(label0: for x 0 5 { (if (eq x 3) (break label0) ) (addto y x) }) (get y)", "012");

        // foreverは永久ループ。breakと組み合わるといいかも。
        assertEval("(label0: (set x 0) [forever { (if (eq x 3) (break label0) ) (set x (add x 1)) (addto y x) }]) (get y)", "123");

        // switch〜case。
        // (switch val { val1 exp1 } { val2 exp2 } ... {default exp0 } )のように書く。
        // val==val1ならexp1が実行される。このときswitchの値は、exp1の評価後の値になる。
        // val==val2ならexp2が実行される。このときswitchの値は、exp2の評価後の値になる。
        // valがそれより前のcaseにおいてどれとも合致していない場合は、default節のexp0が評価され、これがswitchの値となる。
        assertEval("(set x 1)(get {switch x (1 'ABC') (2 'CDE')(3 (mul 2 3) ) } )", "ABC");
        assertEval("(set x 2)(get {switch x (1 'ABC') (2 'CDE')(3 (mul 2 3) ) } )", "CDE");
        assertEval("(set x 3)(get {switch x (1 'ABC') (2 'CDE')(3 (mul 2 3) ) } )", "6");
        assertEval("(set x 5)(get {switch x (1 'ABC') (2 'CDE')(3 (mul 2 3) )(default 'ディフォルト値') } )", "ディフォルト値");
        assertEval("(set x 2)(set y 2)(get {switch x (1 'ABC') (y 'CDE')(3 (mul 2 3) ) } )", "CDE");
  
        // import命令は、ファイルから読み込み、それをS式として式の評価として返す。
        // 読み込むファイルは、//% の行がLISP式として評価されるバージョン

        // test1.cppには" (set x 'ABC')(set y 'DEF')(addto x y) "と書かれているとすると…
        assertEval("(eval (include 'test.lsp'))", "ABCDEF");
        
        // include命令は、ファイルから読み込み、それをS式として式の評価として返す。

        // importはC/C++ /C#のソースファイルを対象とするため、LISP行は、 //% で開始している必要があり、
        // それ以外の行は、文字列として扱われる。
        // 生成元 : Debug/test.cpp → 生成先 : Debug/testout.cpp
        // それぞれのファイルを見ると、何か参考になるかも。
        assertEval("(eval (import 'test.cpp'))", "..done");
        /* // ↓等価
        using (var file = new StreamReader("test.cpp"))
        {
          var exp = new ConvSExp().import(file);
          new Lisp().eval(exp);
        }
        */

        Output.ln( " ********** unittest 正常終了。 **********" );
	}
	catch( Throwable t )
	{
		Output.ln( t.toString );
		Output.ln( " !!!!!!!!!!!!! unittest 失敗 !!!!!!!!!!!!!" );
	}
}

debug( yane_kl ):
import sworks.compo.util.sequential_file;
import sworks.compo.util.dump_members;
void main()
{
	try
	{
		auto ss = new SymbolScope;
		ss.entry!( sworks.klisp.yane_kl );
		auto yf = new YaneFile( "lisp.txt" );
		auto yt = new YaneTokenInclude( yf );
		yt.eval( ss );
//Output.ln( (new YaneFile( "test.cpp"d )).eval!include_filter(ss).toDstringAll );
/*
		auto yf = new YaneFile( "test.cpp", ENCODING.NULL, 2048 );
		for( ; !yf.eof ; )
		{
			auto t = yf.import_filter( yf.nest );
			Output.ln( to!string( t.type ), " : ", t.value );
		}
		Output.ln( yf.getBenchmark.dump_members );
//*/

	}
	catch( Throwable t ) Output.ln( t.toString );

}