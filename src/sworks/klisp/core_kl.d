/** Kara-Lisp で基本機能を持ったLisp-Like言語を記述する。
 * Version:      0.002(dmd2.060)
 * Date:         2012-Nov-14 19:27:08
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.klisp.core_kl;

import std.conv, std.exception, std.ascii;
import sworks.compo.util.output;
private import sworks.klisp.lisp;
private import sworks.klisp.token;
private import sworks.klisp.klisp_file;

/**
 o はじめに
 Kara-Lisp は Lisp パーサとシンボル管理の基本機能を提供します。
ここでは、最も簡単な Lisp Like 言語の実装を通して Kara-Lisp の拡張と使い型を説明します。

 o 全体の流れ
 Kara-Lisp では以下の手順で処理を行います。
1. 定義済みシンボルを準備。
2. ファイル/文字列 からコードの読み込み、dstring に変換する。
3. コードからトークンへと分割。
4. トークンを S式のリストに変換する。
5. どのシンボル同士が対応するかを決定する。
6. 実行。シンボルに関連付けられた(D言語の)関数を実行します。

 o 各段階における拡張方法
 1. 定義済みシンボルを準備。
    シンボルは、sworks.klisp.lisp.SymbolStore が管理しています。
    定義済みシンボルを登録するには、SymbolStore.entry(TYPE)( dstring symbol_name ) を呼び出します。
    この関数の引数として渡せるのは、
    イ. クラス sworks.klisp.lisp.AddressPart へと暗黙変換できる型。
        SymbolStore.entry!Nil( "nil" ); // "nil" という名前で クラス Nil 型のシンボルを SymbolStore に確保する。
    ロ. SExp function(EvalInfo) 型の関数
        SymbolStore.entry!set( "set" );
    ハ. クラス sworks.klisp.lisp.FuncBase を継承した型。
        SymbolStore.entry!QuoteExp( "'" );
    ニ. 構造体、module などの namespace。
        SymbolStore.entry!(sworks.klisp.core_kl); // その namespace に含まれる変数、関数のうち、上記イ、ロ、ハに該当するものが処理される。

 2. ファイル/文字列 からコードの読み込み、dstring に変換する。
    sworks.klisp.klisp_file.TKLispFile が行ないます。
    テンプレート引数として、Lisp コード内で括弧として有効な文字を登録します。
    登録する文字列は、偶数番目の文字と、偶数番+1の文字が対応する括弧になるようにします。
    alias KLispFile = TKLispFile!"()[]{}［］〔〕【】〈〉＜＞《》"d;

    この処理段階で、Lisp コードの括弧の過不足、開き括弧と閉じ括弧の種類の対応がチェックされます。

 3. コードからトークンへと分割。
    sworks.klisp.token.KLispToken を継承したユーザ定義クラスで行います。
    ユーザは、Lisp コード内の空白文字とコメントを読み飛ばすコードを提供して下さい。
    メンバ関数 nextToken が次の1トークンを返すようにします。
    実装の詳細は、sworks.klisp.core_kl.CoreKLToken を参照して下さい。

 4. トークンを S式のリストに変換する。
    sworks.klisp.lisp.KLispCore が行ないます。
    段階 1. において、sworks.klisp.lisp.FuncBase を継承した型を SymbolStore に登録していた場合、
    FuncBase.filter 関数が呼び出され、ユーザが処理を調整出来ます。

 5. どのシンボル同士が対応するかを決定する。
    FuncBase.filter 内で、引数として渡されている SymbolStore に対し、SymbolStore.pushPrefix を呼び出すことで、
    Lisp ファイル内での登場順で、以降でl登場するシンボル名を修飾することができます。
    修飾によってシンボル名の衝突を避けることで、シンボルスコープを提供することが出来ます。

 6. 実行。シンボルに関連付けられた(D言語の)関数を実行します。
    sworks.klisp.lisp.KLispCore が行ないます。
*/


//------------------------------------------------------------------------------
// トークン切り出しに関しての記述
enum BRACKET = "()[]{}［］〔〕【】〈〉＜＞《》"d; // 有効な括弧
enum QUOTE = "\"\"``「」『』"d; // Lisp コードで文字列と認識されるもの。
enum SINGLE_KEYWORD = "';"d ~ BRACKET; // カッコはここに含める。

// 空白文字とコメントを cf 先頭から抜き出す。必要ならばパースは自前で行なう。
class CoreKLToken : KLispToken
{
	enum LINE_COMMENT = ';';

	this( IKLispFile kf ){ super( kf ); } // ここと

	override Token nextToken()
	{
		if( !adjustNest ) return Token(); // ここと
		
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

		return chomp_token!( QUOTE, SINGLE_KEYWORD ); // ここは、まあ定型文
	}
}
alias TKLispFile!( BRACKET ) KLispFile;

//------------------------------------------------------------------------------
// 定義済みシンボル

// これらの変数はダミーでインスタンス化されない。
// AddressPart に暗黙変換でき、引数無しのコンストラクタを持つ型の変数を宣言しておくことで、
// SymbolStore.entry!(sworks.klisp.core_kl)() した際、SymbolStore 内に、変数名でその型のインスタンスが確保される。
T t;
Nil nil;
Undef undefined;

// klisp.lisp.KLFunction 型の関数を定義しておくと
// SymbolStore.entry!(sworks.klisp.core_kl)() した際、SymbolStore に、"writeln" という名前でシンボルが確保される。
// klisp.lisp.KLFunction 型の関数からはパース時に SymbolStore にアクセスすることができない。
// そうした必要のある場合は、FuncBase クラスを継承する形で実装する。
// param は 未eval の状態で渡される。
SExp writeln( EvalInfo ei )
{
	for( auto param = ei.evalAll ; !param.empty ; param.popFront )
	{
		Output( param.toDstring );
		if( null !is param.cdr ) Output( " " );
	}
	Output.ln();
	return SExp();
}

// alias で関数の別名を定義できる。
alias output = writeln;

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
// FuncBase のコンストラクタに関数名を渡しておくと、SymbolStore.entry!(sworks.klisp.core_kl)()
// した際、その名前のシンボルが確保される。
class QuoteExp : FuncBase
{
	// 引数なしのコンストラクタを持つ必要がある。
	this() { super( "'" ); }
	override SExp eval( EvalInfo ei ) { return ei.rest.popFront; }
}

// lisp で関数を定義する defun 関数。
// FuncBase.filter を override しておくと、パース時に呼び出される。
// parse 時、関数名のシンボルに DefunBody クラスのインスタンスを生成しておく。
class Defun : FuncBase
{
	uint counter;
	this(){ super( "defun" ); }

	// 引数 parser に渡された delegate からは、自身が含まれるカッコの内側にアクセスが制限される。
	// parser が null を返したら処理を終るべき。
	// 戻り値をなにか返すと、eval 時に自身の cdr 先頭に追加される。
	override SExp filter( SExp prev_s, SymbolStore ss, Parser parser )
	{
		auto funcsymbol = cast(Symbol)parser().address;
		if( null is funcsymbol )
			throw new KLispMessage( "defun 関数の第一引数は関数名である必要があります。" );
		// ローカルスコープに限定してシンボル名が解決される。
		ss.pushPrefix( "defun"d ~ (counter++).to!dstring, SymbolStore.PRIVATE_MODE_PREFIX );
		auto params_list = parser();
		if( null is cast(List)params_list.address )
			throw new KLispMessage( "defun 関数の第二引数は引数名のリストである必要があります。" );
		// シンボル名の解決がグローバルスコープに及ぶようにする。
		ss.pushPrefix( "body"d, SymbolStore.LOCAL_MODE_PREFIX );
		funcsymbol.contents = SExp( new DefunBody( funcsymbol.name, params_list.car
		                                        , ss.local( "system", 0, "params" ), parser() ) );
		ss.popPrefix;
		ss.popPrefix;
		return SExp();
	}
}
// defun 関数の中身
class DefunBody : AddressPart
{
	dstring name;
	SExp all_params_container;
	SExp params;
	SExp _car;

	this( dstring name, SExp params, SExp apc, SExp car )
	{
		this.name = name;
		this.params = params;
		this.all_params_container = apc;
		this._car = car;
	}

	override SExp eval( EvalInfo ei )
	{
		auto arg = ei.evalAll;
		params.car = arg;
		for( auto p = params ; !arg.empty && !p.empty ; arg.popFront, p.popFront ) p.car = arg;
		return ei.evalAllChild( _car );
	}

	// CTFE 版で使う。
	override dstring toInitializer() @property
	{
		return "new DefunBody(`" ~ name ~ "`, " ~ params.toInitializerAll ~ ", "
		       ~ all_params_container.toInitializer ~ ", " ~ _car.toInitializerAll ~ ")";
	}
}

//
class IfExp : FuncBase
{
	this(){ super( "if" ); }

	override SExp eval( EvalInfo ei )
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

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Run time
debug( core_kl )
{
	import std.conv : to;
	import sworks.klisp.token;

	alias CoreRTKLisp = RTKLisp!( KLispFile, CoreKLToken, ss=>ss.entry!(sworks.klisp.core_kl)() );

	void main()
	{
		try
		{
			(new CoreRTKLisp( "test.kl" )).eval();
		}
		catch( Throwable t ) Output.ln( t.toString );
	}
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Compile Time
// CTFE 版では、Lisp のコードにバグがあった場合、例外メッセージが読めない。
// ↑(例外メッセージ中の日本語がHex値になってるから。)
debug( ct_core_kl )
{
	import std.array, std.conv;
	import sworks.compo.util.output;
	import sworks.klisp.lisp;

	void main()
	{
		try
		{
			(new Test.CTKLisp()).eval();
		}
		catch( Throwable t ) Output.ln( t.toString );
	}

	// alias の場合、シンボル名の参照でおかしくなる。
	mixin CTKLisp!( "test.kl", KLispFile, CoreKLToken, s=>s.entry!(sworks.klisp.core_kl)() ) Test;
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Inline Mode
// 周囲の D言語のスコープにアクセス出来ます。
// int 型、double 型、dstring 型、SExp 型 の変数を参照できます。
debug( inline_core_kl )
{
	import sworks.klisp.lisp;
	void main()
	{
		int x = 100;
		mixin( InlineKLisp!( KLispFile, CoreKLToken, s=>s.entry!(sworks.klisp.core_kl)()
		,"
			; Inline Mode では、周囲のスコープにアクセス出来る。
			(writeln x)
			(set 'x 200)
		"d )() );
		Output.ln( x );
	}
}
