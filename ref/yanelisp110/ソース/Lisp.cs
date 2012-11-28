using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace YaneLisp
{
	// LISPエンジンテスト用
	public class LispTest
	{
		/// <summary>
		/// UnitTest。ここを見れば、使用方法がわかる。
		/// </summary>
		public static void UnitTest()
		{
			try
			{
//				assertEval("(let x (include 'black_and_white.lsp.txt'))", "ABCDEF");

		
				// 文字列とは
				//  quoteされたもの(ダブルコーテイションで囲われたもの or シングルクォートで囲まれたもの、
				//　あと、「」『』で囲まれたもの。ソースはutf-16にて記述する。)
				//  数値、記号(+,-,*,/)で始まるもの
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

				// '' "" 「」　『』で囲まれたものは文字列
				assertEval("(get 「日本語」'も'『使えるよ』)", "日本語も使えるよ");
				assertEval("(get \"【+】\"「'/**/'」'も'『使えるよ』)", "【+】'/**/'も使えるよ");

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

				// replaceは文字置換した値を返す

				// ファイル or 標準出力にoutする。
				//	assertEval("(out 'AAA' 'BBB' 'CCC' )"),"AAABBBCCC");

				// write という、ファイルに出力する命令を用意する。
				// writeは'outfile'という変数に格納されているファイル名のファイルに出力する。
				// (set outfile 'test.log') (write 'ABCDEF') とやれば、
				// test.logに'ABCDEF'が出力される。

				// 2重のforeach
				assertEval("(let list 'x_A' 'x_B' 'x_C')(let list2 'y_A' 'y_B' 'y_C')(foreach e list(foreach e2 list2 (replace (replace 'XXXYYY' 'XXX' e2) 'YYY' e) ))", "y_Ax_Ay_Bx_Ay_Cx_Ay_Ax_By_Bx_By_Cx_By_Ax_Cy_Bx_Cy_Cx_C");

				// 未定義の変数をsetした場合、それをsetした瞬間に評価され、結果は#undefになる。
				assertEval("(set list x_A x_B x_C)", "#undef#undef#undef");

				// これは無限再帰で、再帰が深いので、エラーになる。
				//	assertEval("(let x y)(let y x)(get y)", "x");

				// これは、set y x のときに、xの定義を参照しに行き、そこでyが使われているが、
				// yはまだsetが完了していないので未定義であり、結局、yにはこの未定義であるy(#undef)が
				// 代入される。
				assertEval("(let x y)(set y x)", "#undef");

				// loopは繰り返す…が、最後に評価されたものが式の値になるので結果は最後に評価された式になる。
				assertEval("(loop 3 (get 'ABC')", "ABC");
				assertEval("(loop 3 (get 'ABC')(get 'DEF')", "DEF");

				// 回数は3×5回で15になっているので、きちんとループで実行されていることがわかる。
				assertEval("(set sum 0)(loop 5 (set sum (add sum 3))", "15");

				// loopの回数を指定するところには、変数も指定できる。変数の値は変化しない。
				assertEval("(set total 7)(set sum 0)(loop total (set sum (add sum 3))", "21");

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

				// replaceのなかでメタ文字列の置換を行なう例。
				assertEval("(let x ('AA[' 'XXX')('BB[' 'YYY')('CC[' 'ZZZ') )(set z 'AA[WWWBB[WWWCC[') (foreach e x (set z (replace z (array e 0) (array e 1) ) )) (get z)"
					, "XXXWWWYYYWWWZZZ");

				// regexは正規表現置換
				assertEval("(regex 'AB/*CDE*/FG' '/\\*.*?\\*/' 'XYZ')", "ABXYZFG");

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
				assertEval("(set x 0)(set y 0)(while (neq x 5) ((set x (add x 1)) (set y (add y 3))) (get y)", "15");

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

				// switch～case。
				// (switch val { val1 exp1 } { val2 exp2 } ... {default exp0 } )のように書く。
				// val==val1ならexp1が実行される。このときswitchの値は、exp1の評価後の値になる。
				// val==val2ならexp2が実行される。このときswitchの値は、exp2の評価後の値になる。
				// valがそれより前のcaseにおいてどれとも合致していない場合は、default節のexp0が評価され、これがswitchの値となる。
				assertEval("(set x 1)(get {switch x (1 'ABC') (2 'CDE')(3 (mul 2 3) ) } )", "ABC");
				assertEval("(set x 2)(get {switch x (1 'ABC') (2 'CDE')(3 (mul 2 3) ) } )", "CDE");
				assertEval("(set x 3)(get {switch x (1 'ABC') (2 'CDE')(3 (mul 2 3) ) } )", "6");
				assertEval("(set x 5)(get {switch x (1 'ABC') (2 'CDE')(3 (mul 2 3) )(default 'ディフォルト値') } )", "ディフォルト値");
				assertEval("(set x 2)(set y 2)(get {switch x (1 'ABC') (y 'CDE')(3 (mul 2 3) ) } )", "CDE");

				// その他の関数
				// 次のrandom命令は、0から999までの乱数を返す。
		//		assertEval("(rand 1000)", "1");
                // 返ってくる値がランダムなのでUnitTestが書けず(´ω｀)
				// 0～1までの乱数と2～3までの乱数ならば絶対に一致することはないので
				assertEval("(neq (rand 2)(add 2 (rand 2))", "#true");

				// import命令は、ファイルから読み込み、それをS式として式の評価として返す。
				// 読み込むファイルは、//% の行がLISP式として評価されるバージョン

				// test1.cppには" (set x 'ABC')(set y 'DEF')(addto x y) "と書かれているとすると…
				assertEval("(eval (include 'test.lsp'))", "ABCDEF");
				//	(let x 'ABC')と書かれているファイルだとevalだとまずいのか..

				//  なら↓こうすればいいのか。
				//% (evalstr "(include 'black_and_white.lsp.txt')") 

				assertEval("(evalstr '(add 1 2)')", "3");
//				assertEval("(evalstr 「include 'black_and_white.lsp.txt'」)(get x)","xx"); 
//				assertEval("(let zz (include 'black_and_white.lsp.txt'))(set x (eval zz))(get x)","xx"); 
				// evalが馬鹿ほど評価をする仕様はやめたほうがいいのではないか..

				// eval + include を作った。これならinclude中でletを使っていてもおかしくならない
				assertEval("(evalinclude 'test2.lsp')(print x)", "(add '123' '234')");

				// include命令は、ファイルから読み込み、それをS式として式の評価として返す。

				// importはC/C++/C#のソースファイルを対象とするため、LISP行は、 //% で開始している必要があり、
				// それ以外の行は、文字列として扱われる。
				// 生成元 : Debug/test.cpp →　生成先 : Debug/testout.cpp
				// それぞれのファイルを見ると、何か参考になるかも。
				assertEval("(eval (import 'test.cpp'))", "..done");
				/* // ↓等価
				using (var file = new StreamReader("test.cpp"))
				{
					var exp = new ConvSExp().import(file);
					new Lisp().eval(exp);
				}
				*/

				// YaneCでの変換
				assertEval("(unroller 'void test(){ switch (x) { case 1..5: YYY; }}')",
					"void test ( ) {\r\nswitch ( x ) {\r\ncase 1 : case 2 : case 3 : case 4 : case 5 : YYY ;\r\n}\r\n}\r\n");

			}
			catch (LispException error)
			{
				MessageBox.Show(error.ToString());
			}
		}

		private static string eval(string s)
		{
			return LispUtil.eval(s);
		}

		private static void assertEval(string rvalue, string lvalue)
		{
			assert(eval(rvalue), lvalue , rvalue);
		}

		private static void assert(string rvalue,string lvalue , string evaledString)
		{
			Console.WriteLine("eval(\""+ evaledString +"\") → ");
			if (rvalue != lvalue)
			{
				Console.WriteLine("\n\n\n");
				Console.WriteLine("テストに失敗 : " + rvalue + "!=" + lvalue);
				Console.WriteLine("\n\n\n");
			}
			else
				Console.WriteLine(rvalue);
		}
	}

	// S式を表現するための構造体
	public class SExp
	{
		public object elms;  // element。括弧が深くなるときは、リンク先はSExp。
		// SExp or string(文字列) or VarName or null

		public SExp next;    // 次の要素へのポインタ

		public int sourcePos; // ソース上のポジション
		public int line;      // ソース上の行数
	}

	// 変数名を表わすためのクラス。SExpでelmsとして用いる
	public class VarName
	{
		public string name;
	}

	// Lispで用いる便利関数一式
	public class LispUtil
	{
		// Lisp.evalして、読みやすい形式に変換して返す。
		// 返されたものがstring(文字列)なら、わかるように ' 'で囲って返す。
		public static string eval(string e)
		{
			var lisp = new Lisp();
			var o = lisp.eval(e);
			return lisp.SExp2string(o);
		}

		// Lisp.evalの返し値(SExp)を読みやすい形式に変換して返す。
		// 返されたものがstring(文字列)なら、わかるように ' 'で囲って返す。
		public static string eval(SExp e)
		{
				var lisp = new Lisp();
				var ret = lisp.eval(e);
				return lisp.SExp2string(ret);
		}
	
		// 文字列が ''や""で囲まれていたならそれを除去する
		public static string removeQuote(string s)
		{
			if (isQuoteString(s))
			{
				// 末尾にもあるはずだから、それを除去
				s = s.Substring(1, s.Length - 2);
			}
			return s;
		}

		// ダブルコーテイションで囲まれている文字列なのか？
		public static bool isQuoteString(string s)
		{
			if (s == null || s.Length < 2)
				return false;

			// もしコーテイションが囲われた文字列ならば、コーテイションを外す
			if ("'\"「『".IndexOf(s[0]) >= 0)
				return true;

			return false;
		}

		// 変数名なのかを判定する。
		// 数字・記号で始まる　→　文字列
		// quoteされている　→　文字列
		// それ以外　→　変数名
		public static bool isVariableName(string s)
		{
			char c = s.Length>=1 ? s[0] : '\0';
			return !( ("'\"「『+-*/".IndexOf(c) >= 0) || (c >= '0' && c <= '9') );
		}
	}

	// stringをS式に変換するコンバータ
	public class ConvSExp
	{
		private class Parser
		{
			public Parser(string s)
			{ line = s; }

			private readonly string line;
			public int pos;
			public int linePosCount; // 現在parse中の行
			public string filename;  // 現在読み込み中のファイル名。例外発生時に表示するのに使う。

			// ()の他に [] , {} , 『』 , 《》 なんかも使えるように、それらの括弧がきちんと対応しているかを
			// チェックするために前回の括弧をスタックに積む。
			private readonly Stack<int> bracket = new Stack<int>();

			public string getToken()
			{
				// スペースやセパレータを除外
				while (true)
				{
					if (line.Length <= pos)
						return null; // もうあらへん

					char c = line[pos];
					if ((" \n\r\t".IndexOf(c) < 0))
						break;

					pos++;
				}

				char c0 = line[pos];
				int index = "([{《【〔〈［".IndexOf(c0); 
				if (index >= 0)
				{
					pos++;
					bracket.Push(index);
					return "(";
				}

				index = ")]}》】〕〉］".IndexOf(c0); 
				if (index >= 0)
				{
					if (bracket.Count ==0)
						throw new LispException(CurrentPos + "閉じ括弧が多すぎる。");

					int index2 = bracket.Pop(); // 最後の要素を削除
					if (index != index2)
						throw new LispException(CurrentPos + "括弧が正しく閉じていない。");

					pos++;
					return ")";
				}

				int startPos = pos;

				// " "か、' 'か 「」 で囲まれている文字列なら、それをそのままもらう。
				if ("'\"「『".IndexOf(c0) >= 0)
				{
					pos++;

					if (c0 == '「') c0 = '」'; // この鍵括弧はこれで閉じる
					else if (c0 == '『') c0 = '』';

					// 同じ文字に遭遇するまで。
					while (true)
					{
						if (line.Length == pos /*+ 1*/)
						{
							pos = startPos; // エラー表示のため解析位置を巻き戻す。
							throw new LispException(CurrentPos + "文字列が閉じる前に終端に達した。エラー位置は括弧の開始位置。");
						}

						char c1 = line[pos++];
						
						// スペースやセパレータがあろうと、ともかく同じ文字に遭遇するまで
						if (c0 == c1)
							break;
					}
				} else {
					while (true)
					{
						char c1 = line[pos];
						// スペースやセパレータに遭遇するまで
						if (" \n\t\r'\"()[]{}《》【】「」『』〔〕〈〉［］".IndexOf(c1) >= 0 || line.Length <= pos + 1)
							break;

						pos++;
					}
				}

				if (startPos ==  pos)
					return null; // 空の文字列だった。

				return line.Substring(startPos, pos - startPos);
			}
			// エラーの発生した箇所を表示するための文字列
			private string CurrentPos
			{
				get
				{
					return filename + '(' + linePosCount + ") @" + pos + " : ";
				}
			}
		}

		private static SExp conv2(Parser p,IList<int> linePos)
		{
			var exp = new SExp();
			var startExp = exp;
			while (true)
			{
				var token = p.getToken();
				switch (token)
				{
					case "(":
						exp.elms = conv2(p,linePos);
						exp.sourcePos = p.pos;
						break;
					case ")":
						return startExp;
					default:
						if (token!=null)
						{
							// 数字は無条件で文字列。
							// ダブルコーテイションで囲まれているものも文字列
							// それ以外は、変数名 or 命令だと仮定

							if (LispUtil.isVariableName(token))
							{
								exp.elms = new VarName { name = token };
							}
							else
							{
								exp.elms = LispUtil.removeQuote(token);
							}
							exp.sourcePos = p.pos;
							if (linePos != null)
							{
								exp.line = linePos[p.linePosCount];

								// 対応するソース行の位置を記録しておく。
								while (linePos.Count < p.linePosCount -1
									&& p.pos >= linePos[p.linePosCount + 1])
								{
									p.linePosCount++;
								}
							}
						}
						else
						{
							return startExp; // 最後まで行ってしもた。
						}
						break;
				}
				var exp2 = new SExp();
				// このparser、手抜きなので、最後に nullなobjectがくっつくが、まあそれはいいや
				exp.next = exp2;
				exp = exp2;
			}
		}

		// 文字列をS式に変換。行の位置情報も持っているケース,ファイル名も格納。
		public SExp conv(string s, List<int> linePos, string filename)
		{
			var p = new Parser(s) { filename = filename };
			return conv2(p, linePos);
		}

		// 文字列をS式に変換。行の位置情報も持っているケース
		public SExp conv(string s, List<int> linePos)
		{
			return conv(s, linePos, null);
		}

		// 文字列をS式に変換
		public SExp conv(string s)
		{
			return conv(s,null,null);
		}

		// StreamReaderから読み込んでそれをS式に変換
		// ただし、
		// LISP行は、
		// "//%"で開始している行として、それ以外の行は文字列として扱われる。
		// 例)
		// //% (out
		// void function()
		// //% )
		// このように書けば、void function()が出力される。
		// importで用いる。includeとの違いに注意。
		public SExp import(string filename)
		{
			using (var sr = new StreamReader(filename))
			{
				var sb = new StringBuilder();

				bool quote = false; // ソース引用中か？
				var linePos = new List<int>();

				while (!sr.EndOfStream)
				{
					string line = sr.ReadLine();

					linePos.Add(sb.Length); // 各行に対応するpositionを設定

					if (line.Length >= 3 && line.StartsWith("//%"))
					{
						// 引用中なので終了させる。
						if (quote)
						{
							quote = false;
							sb.Append("』");
						}

						sb.Append(line.Substring(3));
						continue;
					}
					if (!quote)
					{
						// 引用開始
						quote = true; // 引用中フラグon
						sb.Append(" 『");
					}
					sb.AppendLine(line);
				}

				// 引用中なので終了させる。
				if (quote)
				{
					//	quote = false;
					sb.Append("』 ");
				}
				return conv(sb.ToString(), linePos , filename); // 変換してみた。
			}
		}

		// StreamReaderから読み込んでそれをS式に変換
		// このクラスのimportとは異なり、
		// "//%"で開始している行として、それ以外の行は文字列として扱わないバージョン
		public SExp include(string filename)
		{
			using (var sr = new StreamReader(filename))
			{
				var sb = new StringBuilder();
				var linePos = new List<int>();

				while (!sr.EndOfStream)
				{
					string line = sr.ReadLine();

					linePos.Add(sb.Length); // 各行に対応するpositionを設定
					sb.AppendLine(line);
				}

				return conv(sb.ToString(), linePos,filename); // 変換してみた。
			}
		}
	
	}

	// LISP用例外
	public class LispException : Exception
	{
		public LispException(string msg) : base(msg){}
	}

	// LISP本体
	public class Lisp
	{
		#region Lispの実行エンジン
	
		// これ以上深い再帰は行なわない。
		public const int StackMax = 1024;

		public SExp eval(SExp s)
		{
			evalCount++; // evalの深さを測定しておく。

			try
			{

				if (s == null || s.elms == null)
					return null; // 評価不可能

				// 外側のラベルめがけてbreak中なのか？
				if (breakLabel != null)
					return null;

				// 現在実行しているステートメントを例外発生時の表示のために保持しておく。
				evalNow = s;

				var exp = s.elms as SExp;
				if (exp != null)
				{
					// ( (add 1 2) (sub 4 3) )のようにコマンドが並んでいるケース。
					// この場合、後続するリストもすべて実行する必要がある..
					if (s.next != null)
					{
						var o1 = eval(exp);
						var o2 = eval(s.next); // 最後の要素が評価されてこのevalの値になるはずだが
						return o2 ?? o1;
					}
					return eval(exp);
				}

				var command = s.elms as VarName;
				if (command != null)
				{
					stackCount = 0; // stack overflowの防止用

					var name = command.name; // コマンド名

					// コマンド名に見えるものは実はラベルなのか？
					var label = isLabel(name);
					if (label != null)
					{
						labels.Push(label);
						SExp ret = (s.next != null) ? eval(s.next) : null;
						labels.Pop(); // このスコープから抜けるのだから、ラベルはもう不要になる…はず

						// このlabelからbreakしている最中なら、そのbreak labelをリセット
						if (label == breakLabel)
							breakLabel = null;

						return ret;
					}
					else
					{
						// 命令なので実行する。
						return doCommand(name, s);
					}
				}

				// stringなら無視しとけばいいか。
				// return string2SExp( command + "は、evalできない。場所 : " + s.line + " 行 (" + s.sourcePos + ")");

				if (!isNextNull(s))
					return eval(s.next);

				return null; // 駄目ぽ

			}finally
			{
				evalCount--;
				if (evalCount == 0 && breakLabel!=null)
					throw new LispException("breakラベル"+ breakLabel+"が見つからない。" );
			}
		}

		// 文字列を内部的にS式に変換して、そのあとevalする。
		public SExp eval(string s)
		{
			return eval(new ConvSExp().conv(s));
		}

		#region 保持している変数・関数

		// 保持している変数ぜんぶ
		private readonly Dictionary<string, SExp> variables = new Dictionary<string, SExp>();

		// 保持しているローカル変数ぜんぶ
		private readonly Stack<Dictionary<string, SExp>> localVariables = new Stack<Dictionary<string, SExp>>();

		// 保持している関数ぜんぶ
		private readonly Dictionary<string, SExp> functions = new Dictionary<string, SExp>();

		// 保持しているラベルぜんぶ
		private readonly Stack<string> labels = new Stack<string>();

		// breakときのラベル。例外処理のようにstackを巻き戻していく。
		private string breakLabel;

		// 現在の再帰深さ
		private int stackCount;

		// 現在のevalの深さ
		private int evalCount;
		#endregion

		// 再帰が深くなるごとにこれを呼び出すようにする。
		private void incStack()
		{
			stackCount++;
			if (stackCount >= StackMax)
				throw new LispException("再帰が深すぎます。");
		}

		public SExp evalNow = null; // 現在eval中の式
		#endregion

		#region 命令実行部
		private SExp doCommand(string command, SExp s)
		{
			var param = s.next;
			try
			{
				switch (command)
				{
					// 文字列追加
					case "addto":
						return evalAddto(param);

					// 加算
					case "add":
						return evalAdd(param);

					// 減算
					case "sub":
						return evalSub(param);

					// 掛け算
					case "mul":
						return evalMul(param);

					// 割り算
					case "div":
						return evalDiv(param);

					// 配列のgetter
					case "array":
						return evalArray(param);

					// 配列のsetter
					case "setarray":
						return evalSetArray(param);

					case "length":
						return evalLength(param);

					// 出力 console
					case "out":
						return evalOut(param);

					// ファイルにwrite   'outfile'という変数がファイル名を示す。
					case "write":
						return evalWrite(param);

					// 式を評価して、その値を返す
					case "get":
						return evalGet(param);

					// ファイルの削除
					case "del":
						return evalDeleteFile(param);

					// 後ろの値を評価せずに代入
					case "let":
						return evalLet(param);

					// 後ろの値を評価してから代入
					case "set":
						return evalSet(param);

					// 関数の定義用。
					case "func":
						return evalFunc(param);

					case "break":
						return evalBreak(param);

					case "eval":
						return evalEval(param);

//					case "evalweak":
//						return evalEvalWeak(param);

					case "evalinclude":
						return evalEvalInclude(param);

					case "evalimport":
						return evalEvalImport(param);

					case "evalstr":
						return evalEvalStr(param);

					// 文字置換
					case "replace":
						return evalReplace(param);

					// 正規表現置換
					case "regex":
						return evalRegex(param);

					//  foreach
					case "foreach":
						return evalForeach(param);

					// print
					case "print":
						return evalPrint(param);

					// 回数指定繰り返し
					case "loop":
						return evalLoop(param);

					// 小文字化
					case "tolower":
						return evalTolower(param);

					// 大文字化
					case "toupper":
						return evalToupper(param);

					// 条件分岐
					case "if":
						return evalIf(param);

					// ==
					case "eq":
						return evalEq(param);

					// !=
					case "neq":
						return evalNeq(param);

					// and
					case "and":
						return evalAnd(param);

					// or
					case "or":
						return evalOr(param);

					// 制御構造

					// while
					case "while":
						return evalWhile(param);

					// for
					case "for":
						return evalFor(param);

					// downfor ループカウンタが1ずつ減るfor
					case "downfor":
						return evalDownfor(param);

					//  永久ループ
					case "forever":
						return evalForever(param);

					case "switch":
						return evalSwitch(param);

					// 比較演算子

					// less or equal
					case "le":
						return evalLe(param);

					// less than
					case "lt":
						return evalLt(param);

					// greater equal
					case "ge":
						return evalGe(param);

					// greater than
					case "gt":
						return evalGt(param);

					// 本家LISPの機能

					case "car":
						return evalCar(param);

					case "cdr":
						return evalCdr(param);

					// ファイルを読み込み、それをS式とする。
					// ただし、S式は //%で始まる行
					case "import":
						return evalImport(param);

					// ファイルを読み込み、それをS式とする。
					case "include":
						return evalInclude(param);

					// 以下、ユーティリティ
					case "rand":
						return evalRand(param);

					// 以下、unroller(YaneC)
					case "unroller":
						return evalUnroller(param);
				}

				// ユーザー定義関数であれば、それをevalして返す
				if (functions.ContainsKey(command))
				{
					// local変数が使えるようにする。
					// 後続要素を評価して、それらを次のコンテキストのlocal変数に突っ込む
					var local = new Dictionary<string, SExp>();

					int i = 0;
					while (param!=null && param.elms != null)
					{
						// @0,@1,@2,…というローカル変数に突っ込む
						local["@" + i] = Elms2SExp2(param);
						++i;
						param = param.next;
					}

					// ローカル変数コンテキストを切り替える。
					localVariables.Push(local);

					var ret = eval(functions[command]); // 評価

					// ローカル変数コンテキストを戻す
					localVariables.Pop();

					return ret;
				}

			}
			catch (Exception ex)
			{
				string error = command + "で例外発生。 (" + ex.Message + ") 場所 "
							   + s.line + " 行 (" + s.sourcePos + ")";
				Console.WriteLine(error);
				return string2SExp(error);
			}

			// error("Eval不可能な式 :" + command ,s.elms);
			{
				string error = command + "は、evalできない。場所" + s.line + " 行 (" + s.sourcePos + ")";
				Console.WriteLine(error);
				return string2SExp(error);
				// エラーメッセージを文字列として返す。
			}
		}
		#endregion

		#region evalXXX for doCommand
		// 小文字化する。
		private SExp evalTolower(SExp exp)
		{
			return eval_tolower_helper(exp, s => s.ToLower());
		}

		// 大文字化する。
		private SExp evalToupper(SExp exp)
		{
			return eval_tolower_helper(exp, s => s.ToUpper());
		}

		// 加算
		private SExp evalAdd(SExp exp)
		{
			double sum = 0;
			foreach_num(
				exp,
				n => { sum += n; }
			);
			return string2SExp(sum.ToString());
		}

		// 減算 : 第一パラメータから残りのものすべてを引く
		private SExp evalSub(SExp exp)
		{
			double sum = 0;
			bool first = true;
			foreach_num(
				exp,
				n =>
				{
					if (first)
					{
						first = false;
						sum += n;
					}
					else
					{
						sum -= n;
					}
				}
			);
			return string2SExp(sum.ToString());
			// 全部文字列のほうがすっきりする
		}

		// 掛け算
		private SExp evalMul(SExp exp)
		{
			double sum = 1;
			foreach_num(
				exp,
				n => { sum *= n; }
			);
			return string2SExp(sum.ToString());
		}

		// 割り算
		private SExp evalDiv(SExp exp)
		{
			double sum = 1;
			bool isFirst = true;
			foreach_num(
				exp,
				n =>
					{
						if (isFirst)
						{
							sum = n;
							isFirst = false;
						}
						else
							sum /= n;
					}
			);
			return string2SExp(sum.ToString());
		}

		// arrayのN番目の要素を返す、下請け関数
		private static SExp evalArrayOf(SExp exp, long index)
		{
			if (exp == null)
				return SExpNull;
			for (long i = 0; i < index; ++i)
			{
				exp = exp.next;
				if (exp == null)
					return SExpNull;
			}
			return Elms2SExp(exp); // 参照透明なのでcloneする必要がない。
		}

		// 配列の要素にindex指定でアクセスする。
		// (array x 3) のようにしてアクセスする
		private SExp evalArray(SExp exp)
		{
			SExp array = Elms2SExp2(exp);
			var index = eval_getNum(exp.next);

			return evalArrayOf(array, index);
		}

		// arrayのN番目の要素を設定する、下請け関数
		private void evalSetArrayOf(string name, long index,SExp e)
		{
			var exp = getVariable(name);
			if (exp == SExpUndef)
			{
				exp = new SExp {elms = SExpNull};
				setVar(name, exp);
			}

			for (long i = 0; i < index; ++i)
			{
				if (exp.next == null || exp.next.elms == null)
				{
					// どんどん延長するでー
					exp.next = new SExp {elms = SExpNull};
				}
				exp = exp.next;
			}
			exp.elms = e.elms;
		}

		// arrayのN番目の要素に設定する下請け関数
		private SExp evalSetArray(SExp exp)
		{
			var name = eval_getVariname(exp);
			// (setarray x index value) とは、
			// x[index] = value; の意味。valueは単項。

			exp = exp.next;
			var index = eval_getNum(exp);
			exp = exp.next;
			var e = Elms2SExp2(exp);

			evalSetArrayOf(name, index, e);

			return e;
		}

		// arrayの長さを調べる関数。
		private SExp evalLength(SExp exp)
		{
			var e = Elms2SExp2(exp);
			var length = 0;
			while (true)
			{
				if (e == null || e.elms == null)
					break;

				e = e.next;
				++length;
			}

			return string2SExp(length.ToString());
		}

		// car
		// (car x)は (array x 0)と等価
		private SExp evalCar(SExp exp)
		{
			SExp array = Elms2SExp2(exp);
			return evalArrayOf(array, 0);
		}

		// cdr
		private SExp evalCdr(SExp exp)
		{
			SExp array = Elms2SExp2(exp);
			if (isNextNull(array))
				return SExpNull;
			return array.next; // 後続要素
		}

		private SExp evalEval(SExp exp)
		{
			SExp ret = SExpNull;
			foreach_SExp(
				exp,
				o => ret = eval(o) // 二重にevalがかかっている気がする。
				);
			return ret;
		}

		/*
		private SExp evalEvalWeak(SExp exp)
		{
			SExp ret = SExpNull;
			foreach_SExp(
				exp,
				o => ret = o // eval(o) // 二重にevalがかかっている気がする。
				);
			return ret;
		}
		 */
	
		private SExp evalEvalStr(SExp exp)
		{
			// expがstring
			SExp ret = SExpNull;
			foreach_SExp(
				exp,
				o => ret = eval( o.elms as string)
				);
			return ret;
		}

		private SExp evalGet(SExp exp)
		{
			var sb = new StringBuilder();
			foreach_SExp(
				exp,
				o => sb.Append(evalGetInner(o))
				);

			return string2SExp(sb.ToString());
		}

		private SExp evalOut(SExp exp)
		{
			var sb = new StringBuilder();
			foreach_SExp(
				exp,
				o => sb.Append(evalOut_(o))
				);

			string ret = sb.ToString();
			Console.WriteLine(ret);
			return string2SExp(ret);
		}
		
		private SExp evalWrite(SExp exp)
		{
			var sb = new StringBuilder();
			foreach_SExp(
				exp,
				o => sb.Append(evalOut_(o))
				);

			string ret = sb.ToString();
			
			// 出力ファイル名
			var filename = SExp2string(getVar("outfile"));
			if (filename != null && filename != "#undef")
			{
				// BOMで書き出すように変更(2009/11/6) これならBOMが追加される。
				using (var sw = new StreamWriter(filename, true , Encoding.UTF8))
				{
					sw.WriteLine(ret);
				}
			}
			return string2SExp(ret);
		}

		private SExp evalReplace(SExp exp)
		{
			/*
			var o1 = eval_getString(exp);
			exp = exp.next;
			var o2 = eval_getString(exp);
			exp = exp.next;
			var o3 = eval_getString(exp);

			// 文字列置換。

			var regex = new Regex(o2);
			var s = regex.Replace(o1, o3);
			return string2SExp(s);
			 */
			//

			// http://d.hatena.ne.jp/ak11/20091122 のpatch
			var o1 = eval_getString(exp);
			exp = exp.next;

			while (exp != null && exp.elms != null)
			{
				var o2 = eval_getString(exp);
				exp = exp.next;
				var o3 = eval_getString(exp);
				exp = exp.next;

				// 文字列置換。
        // Regexを使うなら、o2からmeta-characterをreplaceしてから。
				//var regex = new Regex(o2);
				//o1 = regex.Replace(o1, o3);
				o1 = o1.Replace(o2,o3);
			}

			return string2SExp(o1);
		}

		private SExp evalRegex(SExp exp)
		{
			var o1 = eval_getString(exp);
			exp = exp.next;

			while (exp != null && exp.elms != null)
			{
				var o2 = eval_getString(exp);
				exp = exp.next;
				var o3 = eval_getString(exp);
				exp = exp.next;

				// 文字列置換。
				// Regexを使うなら、o2からmeta-characterをreplaceしてから。
				var regex = new Regex(o2);
				o1 = regex.Replace(o1, o3);
			}

			return string2SExp(o1);
		}

		private SExp evalForeach(SExp exp)
		{
			// foreach x xs (xxx)

			var name = eval_getVariname(exp);	// 変数名
			exp = exp.next;
			var collection = eval_getVariname(exp);	// コレクション名
			exp = exp.next;
			var e = exp.elms as SExp;				// これが実行すべき式

			var sb = new StringBuilder();

			foreach_collection(
				collection,
				c =>
				{
					setVar(name,Elms2SExp(c));
					sb.Append(SExp2string(eval(e)));
				}
				);

			return string2SExp(sb.ToString());
		}
		// 変数に代入する
		// 変数名は、まったく評価されない。S式としてそのまま代入される。
		private SExp evalLet(SExp exp)
		{
			var name = eval_getVariname(exp);
			
			SExp value = exp.next;
			setVar(name,value);

			return value;
		}

		// 関数とは、まったく評価されずにS式としてそのまま代入される。
		private SExp evalFunc(SExp exp)
		{
			var name = eval_getVariname(exp);

			SExp value = exp.next;
			functions[name] = value;

			return value;
		}

		// ファイル名を指定しての削除
		private SExp evalDeleteFile(SExp param)
		{
			string name = eval_getString(param);

			try
			{
				File.Delete(name);
			}
			catch { }

			return string2SExp(name);
		}

		// 指定回数まわる。
		private SExp evalLoop(SExp exp)
		{
			long u = eval_getNum(exp);

			SExp e = null;
			for (long i = 0; i < u; ++i)
			{
				// これを評価する。
				e = eval(exp.next);

				// break中ならloopを抜けなければ。
				if (breakLabel!=null)
					break;
			}
			return e;
		}

		private SExp evalAddto(SExp exp)
		{
			var name = eval_getVariname(exp);

			SExp e = getVariable(name); // 追加開始する初期文字列として変数の元の値を入れておく
			if (e == SExpUndef)
				e = null;

			foreach_SExp(
				exp.next,
				o => e = concatSExp(e, SExp2cloneReplaceVariable(o))
				);

			setVar(name,e);

			return e;
		}

		// 変数名を評価して代入する
		private SExp evalSet(SExp exp)
		{
			var name = eval_getVariname(exp);
			SExp e = null;
			foreach_SExp(
				exp.next,
				o => e = concatSExp(e, SExp2cloneReplaceVariable(o))
				);

			setVar(name,e);

			return e;
		}

		// ラベルめがけてのbreak(JavaScript風)
		private SExp evalBreak(SExp exp)
		{
			var name = eval_getVariname(exp); // これがbreakラベル
			breakLabel = name;
			return null;
		}

		private SExp evalPrint(SExp exp)
		{
			incStack();

			var sb = new StringBuilder();

			bool isFirst = true;
			foreach_SExp(exp,
			             o =>
			             	{
								if (isFirst)
									isFirst = false;
								else
									sb.Append(" "); // 半角スペースで区切る
			             		sb.Append(evalPrintInner(o));
			             	}
				);

			return string2SExp(sb.ToString());
		}

		// 条件分岐
		private SExp evalIf(SExp param)
		{
			var condition = Elms2SExp2(param);
			param = param.next;

			if (condition == SExpTrue)
				return Elms2SExp2(param);
			if (param.next == null || param.next.elms == null)
				return SExpFalse;
			return Elms2SExp2(param.next);
		}

		// 論理比較

		// ==
		// 比較は中身を評価して、文字列化して、文字列レベルで一致すれば等しいと判定する。
		private SExp evalEq(SExp param)
		{
			var elms1 = Elms2SExp2(param);
			var elms2 = Elms2SExp2(param.next);

			return SExp2string(elms1) == SExp2string(elms2)
			       	? SExpTrue : SExpFalse;
		}

		// !=
		private SExp evalNeq(SExp param)
		{
			var elms1 = Elms2SExp2(param);
			var elms2 = Elms2SExp2(param.next);

			return SExp2string(elms1) != SExp2string(elms2)
					? SExpTrue : SExpFalse;

		}

		// le
		private SExp evalLt(SExp param)
		{
			var elms1 = eval_getNumDouble(param);
			var elms2 = eval_getNumDouble(param.next);

			return elms1 < elms2
					? SExpTrue : SExpFalse;
		}

		// le
		private SExp evalLe(SExp param)
		{
			var elms1 = eval_getNumDouble(param);
			var elms2 = eval_getNumDouble(param.next);

			return elms1 <= elms2
					? SExpTrue : SExpFalse;
		}

		// gt
		private SExp evalGt(SExp param)
		{
			var elms1 = eval_getNumDouble(param);
			var elms2 = eval_getNumDouble(param.next);

			return elms1 > elms2
					? SExpTrue : SExpFalse;
		}

		// ge
		private SExp evalGe(SExp param)
		{
			var elms1 = eval_getNumDouble(param);
			var elms2 = eval_getNumDouble(param.next);

			return elms1 >= elms2
					? SExpTrue : SExpFalse;
		}

		// 論理and(&&)
		private SExp evalAnd(SExp param)
		{
			var elms1 = Elms2SExp2(param);
			var elms2 = Elms2SExp2(param.next);

			// 			return (elms1 == SExpTrue && elms2 == SExpTrue)
			//		↑これだと、user側が#true定数を作れなくて困る？(´ω｀)

			return (SExp2string(elms1) == "#true" && SExp2string(elms2) == "#true")
					? SExpTrue : SExpFalse;
		}

		// 論理or(||)
		private SExp evalOr(SExp param)
		{
			var elms1 = Elms2SExp2(param);
			var elms2 = Elms2SExp2(param.next);

			return (SExp2string(elms1) == "#true" || SExp2string(elms2) == "#true")
					? SExpTrue : SExpFalse;
		}

		// while文
		private SExp evalWhile(SExp param)
		{
			SExp ret = SExpNull;
			while (true)
			{
				var condition = Elms2SExp2(param);

				if (breakLabel!=null || SExp2string(condition) != "#true")
					return ret;

				ret = Elms2SExp2(param.next); // これこの時点で評価されるので1回実行されたことになる
			}
		}

		// for文
		// (for i 0 10 式)
		// みたいな形で使う。
		private SExp evalFor(SExp param)
		{
			var varname = eval_getVariname(param);
			param = param.next;
			var startValue = eval_getNum(param);
			param = param.next;

			SExp ret = null;

			long i = startValue;
			while (i <= eval_getNum(param) && breakLabel == null)
			{
				setVar(varname,string2SExp(i.ToString()));
				ret = Elms2SExp2(param.next); // これこの時点で評価されるので1回実行されたことになる
				i++;
			}
			// このループカウンタ、消滅させておく必要がある。
			deleteVar(varname);

			return ret;
		}

		// forのループカウンタが逆方向に動くバージョン
		private SExp evalDownfor(SExp param)
		{
			var varname = eval_getVariname(param);
			param = param.next;
			var startValue = eval_getNum(param);
			param = param.next;

			SExp ret = null;

			long i = startValue;
			while (i >= eval_getNum(param) && breakLabel == null)
			{
				setVar(varname,string2SExp(i.ToString()));
				ret = Elms2SExp2(param.next); // これこの時点で評価されるので1回実行されたことになる
				i--;
			}
			// このループカウンタ、消滅させておく必要がある。
			deleteVar(varname);

			return ret;
		}

		// forever文
		private SExp evalForever(SExp param)
		{
			SExp ret = SExpNull;
			// forever文からはbreakによってしか抜け出すことは出来ない。
			while (breakLabel == null)
			{
				ret = Elms2SExp2(param); // これこの時点で評価されるので1回実行されたことになる
			}
			return ret;
		}

		private SExp evalSwitch(SExp param)
		{
			var val = eval_getString(param); // switch(val) { case val1 ... }
			param = param.next;

			// case節を順番に調べていく。
            while (param != null && param.elms!=null && breakLabel==null )
			{
				if (param.elms is SExp)
				{
					var caseval = param.elms as SExp;
					if (
						(caseval.elms is VarName && (caseval.elms as VarName).name == "default") // default節か？
						||
						(eval_getString(caseval) == val) // caseラベルと一致したのか
						)
					{
						if (caseval.next == null || caseval.next.elms == null)
							throw new LispException("switchのcase節に命令が書かれていない。");

						return Elms2SExp2(caseval.next); // caseに書かれている式を評価。
					}
				}
				else
				{
					throw new LispException("switchのcase節がおかしい。");
				}
				param = param.next;
			}
			return SExpNull;
		}


		private SExp evalImport(SExp param)
		{
			var f = eval_getString(param);
			return new ConvSExp().import(f);
		}

		private SExp evalInclude(SExp param)
		{
			var f = eval_getString(param);
			return new ConvSExp().include(f);
		}

		// include後、一度だけevalする
		private SExp evalEvalInclude(SExp param)
		{
			var f = eval_getString(param);
			return eval(new ConvSExp().include(f));
		}

		// import後、一度だけevalする
		private SExp evalEvalImport(SExp param)
		{
			var f = eval_getString(param);
			return eval(new ConvSExp().import(f));
		}

		private readonly Random rand = new Random();
		private SExp evalRand(SExp param)
		{
			var r = eval_getNum(param);
			return string2SExp( rand.Next((int)r).ToString() );
		}

		private SExp evalUnroller(SExp param)
		{
			var f = eval_getString(param);
			var u = new YaneUnroller.Unroller();
			var tree = u.ParseProgram(f);
			return string2SExp(tree.ToString());
		}

		#endregion

		#region const for LISP
		public static readonly SExp SExpUndef = new SExp { elms = "#undef" };
		public static readonly string SExpNullString = "#null";
		public static readonly SExp SExpNull = new SExp { elms = SExpNullString };
		public static readonly SExp SExpTrue = new SExp { elms = "#true" };
		public static readonly SExp SExpFalse = new SExp { elms = "#false" };
		#endregion

		#region foreach for eval

		public void error(string mes , object exp)
		{
			var e = exp as SExp;
			int pos1 = e != null ? e.sourcePos : -1;
			int line1 = e != null ? e.line : -1;
			int pos2 = evalNow != null ? evalNow.sourcePos : -1;
			int line2 = e != null ? e.line : -1;
			throw new LispException("LISP実行エラー : " + mes + " ソース位置 : " + pos1 + " in " + line1 + ", 親Error位置 : " + pos2 + " in " + line2);
		}

		// exp.elmsに保持している変数名を取得する。ダブルコーテイションで囲まれた文字列はエラーになる。
		// SExpの場合、それを評価して文字列化する。
		private string eval_getVariname(SExp exp)
		{
			if (exp.elms is SExp)
			{
				return SExp2string( eval(exp.elms as SExp) );
			}
			
			// 変数名を意味する文字列のはずなので、これをそのまま返す
			// 文字列のはずだが、これがダブルコーテイションで囲われていたり、数値であったりしてはいけない。
			var ss = exp.elms as VarName;
			if (ss == null)
				throw new LispException("変数名が来ていない。");
			if (!LispUtil.isVariableName(ss.name))
				throw new LispException("変数名として"+ss+"はおかしい。");
			// 何故変数名が " "で囲われているのかは知らないが
			// 本来ありえないはず。

			return ss.name;
		}

		// exp.elmsがS式ならそれを評価して文字列化して返す。文字列ならそのまま返す。変数名なら評価して返す。
		private string eval_getString(SExp exp)
		{
			return SExp2string(Elms2SExp2(exp));
		}

		// 変数名を入れて、それに対応する内容を得る。
		// 未定義の場合、#undefが返る。
		private SExp getVariable(string name)
		{
			SExp o = null;
			if (LispUtil.isVariableName(name))
			{
				o = existVar(name) ? getVar(name) : SExpUndef;
					//	error(name + "という変数は未定義", e);
			}
			return o;
		}

		// SExpの最初のエレメントの持っている文字列を取得する。
		public string SExp2string(SExp exp)
		{
			if (exp == null || exp.elms == null)
				return "";

			var elms = exp.elms;
			string s;
			if (elms is VarName)
				s = "#VarName:" + (elms as VarName).name;
			else if (elms is SExp)
				s = SExp2string(elms as SExp); // 再帰的に文字列化
			else if (elms is string)
				s= elms as string;
			else 
				s = "#noname";

			return s + (!isNextNull(exp) ? SExp2string(exp.next) : "");
		}

		// exp.elmsがS式ならそれを評価して文字列化、文字列ならそのまま。
		// そして、それを数値にparseして返す
		private long eval_getNum(SExp exp)
		{
			if (exp == null || exp.elms == null)
				return 0;

			long u;
			try
			{
				u = long.Parse(eval_getString(exp));
			}
			catch
			{
				u = 0;
			}
			return u;
		}

		// eval_getNumのdoubleで返す版
		private double eval_getNumDouble(SExp exp)
		{
			if (exp == null || exp.elms == null)
				return 0;

			double u;
			try
			{
				u = double.Parse(eval_getString(exp));
			}
			catch
			{
				u = 0;
			}
			return u;
		}

		// S式の内容を評価する。
		private void foreach_SExp(SExp exp, Action<SExp> dg)
		{
			while (exp != null && exp.elms != null && breakLabel == null)
			{
				dg(Elms2SExp2(exp));
				exp = exp.next;
			}
		}

		private void foreach_num(SExp exp, Action<double> dg)
		{
			while (exp != null && exp.elms != null && breakLabel == null)
			{
				dg(eval_getNumDouble(exp));
				exp = exp.next;
			}
		}

		private void foreach_collection(string collectionName, Action<SExp> dg)
		{
			var exp = getVar(collectionName);
			while (exp != null && exp.elms!=null && breakLabel==null)
			{
				dg(exp);
				exp = exp.next;
			}
		}
	
		#endregion

		#region helper関数いろいろ

		// 文字列をS式にして返す
		private static SExp string2SExp(string s)
		{
			return new SExp { elms = s };
		}
		// SExpなら #SExp , stringならそのままstring , nullなら #NULL と変換するヘルパ
		private static string SElm2String(object exp)
		{
			if (exp is SExp)
				return "#SExp";
			if (exp is string)
				return exp as string;
			if (exp is VarName)
				return (exp as VarName).name;
			if (exp == null)
				return SExpNullString;

			return "#error"; // 変換不能なり
		}

		private string evalGetInner(object exp)
		{
			incStack();


			if (exp is string)
			{
				return exp as string; // そのまま返す
			}
			if (exp is VarName)
			{
				return (exp as VarName).name;
			}
			if (exp is SExp)
			{
				var elms = (exp as SExp).elms;

				if (elms == null)
					return "";

				string s;
				if (elms is SExp)
				{
					// 子要素の評価もする。
					s = SExp2string(eval(elms as SExp));
				} else if (elms is VarName)
				{
					// ここに、この変数を評価したものが入る。再帰的に入る。
					s =  SExp2string( evalGet(getVariable((elms as VarName).name)) );
				}
				else
				{
					s = SElm2String(elms);
				}

				return s + (!isNextNull(exp as SExp) ? evalGetInner((exp as SExp).next) : "");

			}

			return SExpNullString;
		}

		private string evalOut_(object o)
		{
			incStack();

			var exp = o as SExp;
			if (exp == null)
			{
				var s = o as string;
				if (s != null)
					return s;

				return ""; // 可視不可能
			}
			var sb = new StringBuilder();

			while (true)
			{
				if (exp.elms is SExp)
				{
					//	sb.Append("(" + evalOut_(exp.elms as SExp) + ")");
					sb.Append(evalOut_(exp.elms as SExp));
					// 中身は単純に文字列に変換されて連結されているほうが良い。
				}
				else if (exp.elms is string)
				{
					sb.Append(exp.elms as string);
				}
				// それ以外は表示不可能なので無視

				if (isNextNull(exp))
					break;
	
				exp = exp.next;

				//	sb.Append(' '); // このスペース入れてあったほうがいいかなぁ…。
			}

			return sb.ToString();
		}

		// SExp同士を連結する
		private static SExp concatSExp(SExp e1, SExp e2)
		{
			var exp = e1;
			if (e1 == null)
				return e2;

			while (true)
			{
				if (isNextNull(exp) )
				{
					exp.next = e2;
					return e1;
				}
				exp = exp.next;
			}

			// expをe2に置換する。すなわち、一つ前のに置換してしまう。
		}

		// 変数名を実体に置換しながら、Cloneしていく。
		private SExp SExp2cloneReplaceVariable(SExp exp)
		{
			incStack();

			var elms = exp.elms;
			if (elms is SExp)
			{
				var el = elms as SExp;
				var newexp = new SExp {elms = SExp2cloneReplaceVariable(el)};
				if (!isNextNull( exp.next ) )
					newexp.next = SExp2cloneReplaceVariable(exp.next);
				return newexp;
			}
			if (elms is VarName)
			{
				// これを評価して返す必要がある。
				var el = getVariable((elms as VarName).name);
				var newexp = new SExp { elms = SExp2cloneReplaceVariable(el) };
				newexp = concatSExp(newexp,SExp2cloneReplaceVariable(exp.next));
				return newexp;
			}
			if (elms is string)
			{
				// stringは参照透明なので、cloneする必要はない。
				var newexp = new SExp { elms = elms };
				if (!isNextNull( exp ) )
					newexp.next = SExp2cloneReplaceVariable(exp.next);
				return newexp;
			}
			// それ以外ってnullか？
			return null;
		}


		// SExpの中身を何も評価せずに忠実に文字列化して表示する。
		// SExpConvでこれをそのままS式にしてeval可能である。
		private string evalPrintInner(SExp exp)
		{
			incStack();

			var sb = new StringBuilder();

			while(exp!=null && exp.elms!=null)
			{
				object elms = exp.elms;

				if (elms is string)
					sb.Append("'" + elms + "'");
				else if (elms is VarName)
					sb.Append((elms as VarName).name);
				else if (elms is SExp)
					sb.Append("(" + evalPrintInner(elms as SExp) + ")");
				else
					sb.Append(SExpNullString); // あってはならないのだが

				// 後続要素があるならスペースを入れておく
				if (!isNextNull(exp) )
					sb.Append(" ");

				exp = exp.next;
			}

			return sb.ToString();
		}


		// tolowerなど (tolower x 'AAA') のような形でパラメータをとるタイプの
		// 命令を簡単に実装できるようにするためのヘルパクラス
		private SExp eval_tolower_helper(SExp exp, Func<string, string> dg)
		{
			// 代入する変数
			if (!(exp.elms is VarName))
				return null; 

			var name = (exp.elms as VarName).name;

			// そこ以降を文字列として連結する。
			var s = SExp2string(evalGet(exp.next));

			return setVar(name , string2SExp(dg(s)));
		}

		// ElmsをSExpに
		// x = ( exp1 exp2 exp3) のようなコレクションに対してforeachで回すときに使う。
		// exp = exp1 を指しているとき、これを参照透明と仮定して、SExpに包みたい
		// ときに使う
		private static SExp Elms2SExp(SExp exp)
		{
			var elms = exp.elms;
			SExp ret = null;
			if (elms is string)
				ret = string2SExp(elms as string);
			else if (elms is SExp)
				ret = elms as SExp;
			else if (elms is VarName)
				// ここに来て変数名かよ..
				ret = new SExp {elms = exp};

			return ret;
		}

		// expのElmsをSExpに変換その2
		// 変数名 → 中身のSExp
		// 文字列 → WrapしたSExp
		// SExp   → 評価してSExpとして返す
		// (eq param1 param2)　のような形でパラメータをとる関数に使うと良い。
		private SExp Elms2SExp2(SExp exp)
		{
			if (exp == null)
				return SExpNull;
			var elms = exp.elms;
			if (exp == null)
				return SExpNull;

			if (elms is VarName)
			{
				return getVariable((elms as VarName).name); 
			}
			if (elms is string)
			{
				return string2SExp(elms as string);
			}
			if (elms is SExp)
				return eval(elms as SExp);

			return SExpNull;
		}

		// SExpに対して、その後続要素がnullであるかどうか。
		private static bool isNextNull(SExp exp)
		{
			return exp == null || exp.next == null || exp.next.elms == null;
		}

		// 変数名だと思っていたものは実はラベルなのか？
		// 変数名ならnullを返す。ラベルならば、末尾の':'を除去して返す
		private static string isLabel(string varname)
		{
			if (string.IsNullOrEmpty(varname))
			{
				return null;
			}

			// 末尾が':'ならば、これはラベルである。
			if (varname[varname.Length - 1] == ':')
				return varname.Substring(0, varname.Length - 1);

			return null;
		}

		#endregion

		#region 変数にアクセスするアクセッサ
		// 変数名を指定して、その変数を削除する。
		// その変数が存在しなければ何もしない。
		public void deleteVar(string name)
		{
			if (string.IsNullOrEmpty(name))
				return ;

			if (name[0] == '@')
			{
				if (localVariables.Peek().ContainsKey(name))
					localVariables.Peek().Remove(name);
			}
			else if (variables.ContainsKey(name))
			{
				variables.Remove(name);
			}
		}

		// 指定した変数名の変数が存在するのか?
		public bool existVar(string name)
		{
			if (string.IsNullOrEmpty(name))
				return false;

			if (name[0] == '@')
				return localVariables.Count!=0 && localVariables.Peek().ContainsKey(name);

			return variables.ContainsKey(name);
		}

		// 指定した変数名の変数を返す。存在しなければnull
		public SExp getVar(string name)
		{
			if (string.IsNullOrEmpty(name))
				return null;

			// ロカール変数は必ず@で開始される。
			if (name[0] == '@')
			{
				if (localVariables.Count == 0)
					throw new LispException("トップレベルでローカル変数は使えない。");

				if (localVariables.Peek().ContainsKey(name))
					return localVariables.Peek()[name];

				return null;
			}
			if (variables.ContainsKey(name))
			{
				return variables[name];
			}
			return null;
		}

		// 変数名に値を設定する。
		public SExp setVar(string name, SExp exp)
		{
			// 変数名が@で始まるなら、それはlocal変数
			if (string.IsNullOrEmpty(name))
				return null;

			if (name[0] == '@')
			{
				if (localVariables.Count == 0)
					throw new LispException("トップレベルでローカル変数は使えない。");

				return localVariables.Peek()[name] = exp;
			}

			return variables[name] = exp;
		}
		#endregion
	}
}
