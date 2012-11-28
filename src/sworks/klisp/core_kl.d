/** Kara-Lisp で基本機能を持ったLisp-Like言語を記述する。
 * Version:      0.002(dmd2.060)
 * Date:         2012-Nov-14 19:27:08
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.klisp.core_kl;

import std.exception, std.ascii;
import sworks.compo.util.output;
private import sworks.klisp.lisp;
private import sworks.klisp.token;
private import sworks.klisp.klisp_file;

// トークン切り出しに関しての記述
enum BRACKET = "()[]{}［］〔〕【】〈〉＜＞《》"d;
enum QUOTE = "\"\"``「」『』"d;
enum SINGLE_KEYWORD = "';"d ~ BRACKET;

// 空白文字とコメントを cf 先頭から抜き出す。必要ならばパースは自前で行なう。
Token core_kl_token_filter( IKLispFile cf, int nest_level )
{
	enum LINE_COMMENT = ';';

	for( dchar d = cf.peek ; '\0' != d ; )
	{
		if( LINE_COMMENT == d )
		{
			for( ; ; )
			{
				d = cf.discard;
				if( '\0' == d || cf.newline ) break;
			}
		}
		else if( d.isWhite ) d = cf.discard;
		else break;
	}
	return Token();
}
alias _nextToken!( core_kl_token_filter, QUOTE, SINGLE_KEYWORD ) token_filter;
alias _KLispFile!( BRACKET ) KLispFile;

// これらの変数はダミーでインスタンス化されない。
// SExp に暗黙変換でき、引数無しのコンストラクタを持つ型の変数を宣言しておくことで、
// SymbolScope.entry!(sworks.klisp.core_kl)() した際、SymbolScope 内に、変数名でその型のインスタンスが確保される。
T t;
Nil nil;
Undef undefined;

// klisp.lisp.KLFunction 型の関数を定義しておくと
// SymbolScope.entry!(sworks.klisp.core_kl)() した際、SymbolScope に、"writeln" という名前でシンボルが確保される。
// klisp.lisp.KLFunction 型の関数からは SymbolScope にアクセスすることができない。
// そうした必要のある場合は、FuncBase クラスを継承する形で実装する。
// param は 未eval の状態で渡される。
SExp writeln( EvalInfo ei )
{
	auto param = ei.evalAll;
	for( ; !param.empty ; param.popFront )
	{
		Output( param.toDstring );
		if( null !is param.cdr ) Output( " " );
	}
	Output.ln();
	return SExp();
}

// alias で関数の別名を定義できる。
alias writeln output;

//
SExp set( EvalInfo ei )
{
	auto param = ei.evalAll;
	auto symbol = param.popFront;
	auto val = param.popFront;
	symbol.car = val;
	return SExp();
}

// 特殊な関数名を持つものは、FuncBase クラスを継承することで定義できる。
// FuncBase のコンストラクタに関数名を渡しておくと、SymbolScope.entry!(sworks.klisp.core_kl)()
// した際、その名前のシンボルが確保される。
class QuoteExp : FuncBase
{
	// 引数なしのコンストラクタを持つ必要がある。
	this() { super( "'" ); }
	override SExp eval( EvalInfo ei ) { return ei.rest.popFront; }
}

// lisp で関数を定義する defun 関数。
// FuncBase.filter を override しておくと、パース時に呼び出される。
// parse 時、関数名のシンボルに Defun.FuncBody クラスのインスタンスを生成しておく。
class Defun : FuncBase
{
	this(){ super( "defun" ); }

	// 引数 parser に渡された delegate からは、自身が含まれるカッコの内側にアクセスが制限される。
	// parser が null を返したら処理を終るべき。
	// 戻り値をなにか返すと、eval 時に自身の cdr 先頭に追加される。
	override SExp filter( SymbolScope parent_ss, Parser parser )
	{
		auto symbol_scope = new SymbolScope; // <- parent_ss 渡さない。
		auto funcsymbol = cast(Symbol)parser( parent_ss ).address;
		if( null is funcsymbol )
			throw new KLispMessage( "defun 関数の第一引数は関数名である必要があります。" );
		auto params_list = parser( symbol_scope ); // ローカルスコープに限定してシンボル名が解決される。
		if( null is cast(List)params_list.address )
			throw new KLispMessage( "defun 関数の第二引数は引数名のリストである必要があります。" );

		symbol_scope.parent = parent_ss; // シンボル名の解決がグローバルスコープに及ぶようにする。
		funcsymbol.contents = SExp( new FuncBody( funcsymbol.name, symbol_scope
		                                        , params_list.car, parser( symbol_scope ) ) );
		return SExp();
	}

	class FuncBody : AddressPart
	{
		dstring name;
		SymbolScope symbol_scope;
		SExp params;
		SExp _car;

		this( dstring name, SymbolScope ss, SExp params, SExp car )
		{
			this.name = name;
			this.symbol_scope = ss;
			this.params = params;
			this._car = car;
		}

		override SExp eval( EvalInfo ei )
		{
			auto arg = ei.evalAll;
			symbol_scope.local( "params"d, arg );
			for( auto p = params ; !arg.empty && !p.empty ; arg.popFront, p.popFront ) p.car = arg;
			return ei.evalAllChild( _car );
		}
	}
}

class IfExp : FuncBase
{
	this(){ super( "if" ); }

	SExp eval( EvalInfo ei )
	{
		SExp result;
		if     ( ei.popEval.toBool ) result = ei.popEval;
		else
		{
			ei.rest.popFront;
			result = ei.popEval;
		}
		ei.rest = SExp();
		return result;
	}
}

debug( core_kl ):
import std.conv : to;
import sworks.klisp.token;
void main()
{
	try
	{
		auto ss = new SymbolScope;
		ss.entry!(sworks.klisp.core_kl);
//*
		(new KLispFile( "test.kl" )).eval!token_filter( ss );
/*///*
		auto kf = new KLispFile( "test.kl" );
//*
		for( ; !kf.eof ; )
		{
			Output.ln( kf.parse!token_filter( ss, kf.nest ).toDstring );
		}

/*//*
		Token t;
		for( ; !kf.eof ; )
		{
			t = kf.token_filter( kf.nest );
			Output.ln( kf.nest, ", ", t.type.to!string, " : ", t.value );
		}
		kf.close;
//*/
	}
	catch( Throwable t ) Output.ln( t.toString );
}
