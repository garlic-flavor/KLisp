using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;

namespace YaneUnroller
{
	public class UnrollerTest
	{
		/// <summary>
		/// 構文解析/変換のテスト
		/// </summary>
		public static void Test()
		{
			var u = new YaneUnroller.Unroller();

			var test_statement = new[]
			                     	{
			                     		"z = x < y ? 1 : 2;",
			                     		"x = 	1 + 2 * 3 + ~(4 / 5);",
			                     		"foreach(sq in bb_pawn) target &= abb_mask[sq];",
			                     		"foreach:enum(e in XXX) x += e;",
			                     		"foreach(u32 sq in abc_def ) target &= abb[sq];",
			                     		"foreach(n in nsquare ) sum+=n;",
			                     		"unroll case { case 1: x++;  case 2: y++; case 4: z++; }",
			                     		"unroll case { case AA: x++;  case BB: y++; case CC: z++; }",
			                     		"switch (x) { case 3..7: xxx; }",
			                     		"avoid \"case 4 : … case 8 :\"switch(xxx) { case 3..10 : AAA; }",
			                     		"avoid \"case 4 : … case 8 : … break ;\" switch(xxx) { case 3: case 4 : break; case 8: AAA; break; case 9: AAA; }"
			                     		,
			                     		"{ closure AAA(BBB) { CCC; BBB; }  AAA { DDD; } }",
			                     		"unroll foreach XXX in 0,3,6..10,ABC { abcd[XXX]++; }",
			                     		"for(int i=0;i<10;++i) printf(\"abc\");",
			                     		"while(true) { println(); break; }",
			                     	};

			var test_program = new[]
			                   	{
			                   		"void test(int x,int y,Move* move){ printf(\"abc\"); }",
			                   		"int x = 123;",
			                   		"int a[] = { 1,2,3};"
			                   	};

			foreach (var p in test_statement)
			{
				Console.WriteLine("original → " + p);
				var tree = u.ParseStatement(p);
				Console.WriteLine(tree.ToTreeString());
				Console.WriteLine(tree.ToString());
				Console.WriteLine();
			}

			foreach (var p in test_program)
			{
				Console.WriteLine("original → " + p);
				var tree = u.ParseProgram(p);
				Console.WriteLine(tree.ToTreeString());
				Console.WriteLine(tree.ToString());
				Console.WriteLine();
			}
		}
	}
	
	/// <summary>
	/// C/C++でソースを展開したりするのに使うunroller
	/// </summary>
	public class Unroller
	{
		// Unrollしたいプログラムをまるごと↓のstringに突っ込んで渡す。
		public string Unroll(string program)
		{
			tokenizer = new Tokenizer();
			tokenizer.SetProgram(program);

			SyntaxTree st;
			try
			{
				st = Program();
			}catch(UnrollerException ex)
			{
				throw new UnrollerException(ex + " @ line = " + tokenizer.Line);
			}
			return st.ToString();
		}

		// その他、自分で使うプログラムのクラス名を追加しておくといいかも。
		public List<string> TypeNames
		{
			get { return tokenizer.TypeNames; }
		}

		// デバッグ用のparser
		public SyntaxTree ParseProgram(string program)
		{
			tokenizer = new Tokenizer();
			tokenizer.SetProgram(program);
			return Program();
			// ここ↑を適当に変えて、parseしたい文法をparseさせてテストする
		}

		// デバッグ用のparser
		public SyntaxTree ParseStatement(string program)
		{
			tokenizer = new Tokenizer();
			tokenizer.SetProgram(program);
			return StatementSequence();
			// ここ↑を適当に変えて、parseしたい文法をparseさせてテストする
		}

		private Tokenizer tokenizer;
		
		/// <summary>
		/// parserからtokenをひとつ取り除く
		/// </summary>
		/// <returns></returns>
		private void RemoveToken()
		{
			tokenizer.GetToken();
			tokenizer.PeekToken();
		}

		/// <summary>
		/// parserからtokenをひとつ得る。取り除きはしない。
		/// </summary>
		/// <returns></returns>
		private Token Token
		{
			get
			{
				return tokenizer.PeekToken();
			}
		}

		/// <summary>
		/// GetTokenしたときのIdent
		/// </summary>
		private string Ident
		{
			get { return tokenizer.Ident; }
		}

		//--- 以下、構文解析

		public SyntaxTree Program()
		{
			// { [ Function | FunctionDeclare | VariableDeclare | Include | Define | ClassDefine | EnumDefine
			// | ClassDeclare | EnumDeclare] }.
			var tree = CreateSyntaxTree(Syntax.Program);

			while (true)
			{
				switch (Token)
				{
					case Token.TYPENAME:
					case Token.IDENT:
						// これは
						// Function | FunctionDeclare | VariableDeclare
						// の型名だろう
						var tree2 = CreateSyntaxTree(Syntax.Function); // とりあえず格納しておくための入れ物
						tree2.Append(Token); // ident or typename
						if (Token == Token.MUL)
						{
							tree2.Append(Token); // 型名 "*"
						}
						tree2.Append(Token.IDENT);	// function name or variable name..
						//Function,					 // typename funcname "(" FunctionParameters ")" StatementSequence.
						if (Token == Token.LPAREN)	// "(" この時点でfunction系 確定
						{
							tree2.Append(Token);
							tree2.Append(FunctionParameters());
							tree2.Append(Token.RPAREN);
							tree2.Append(StatementSequence());	// 宣言だけなら本体がない。

							tree.Append(tree2);
							break;
						}
            // 変数宣言だな。
						tree2.syntax = Syntax.VariableDeclare; // 変更しておく。

						// int n[3] = { 1 , 2 , 3};
						var selector = Selector();
						if (selector!=null)
							tree2.Append(selector);

						if (Token == Token.EQUAL)
						{
							// 初期化子がついているのか。
							tree2.Append(Token);

							tree2.Append(InitExpression()); 
						}
						tree2.Append(Token.SEMICOLON);
						tree.Append(tree2);

						break;

					case Token.EOF:
						return tree;
				}
			}
		}

		// 代入のときの初期化子。
		public SyntaxTree InitExpression()
		{
			// Expression | "{" {InitExpression {"," InitExpression } "}".
			var tree = CreateSyntaxTree(Syntax.InitExpression);
			if (Token == Token.LBRACE)
			{
				tree.Append(Token.LBRACE); // "{"
			Next:
				tree.Append(InitExpression());
				if (Token == Token.COMMA)
				{
					tree.Append(Token);
					goto Next;
				}
				tree.Append(Token.RBRACE); // "}"
			} else
			{
				tree.Append(Expression());
			}

			return tree;
		}

		public SyntaxTree FunctionParameters()
		{
			//FunctionParameters,// { ["const"] typename {"*" | "&"} ident } { "," ["const"] typename ["*" | "&"] ident }
			//VariableDeclare    // typename statement (assignement)
			var tree = CreateSyntaxTree(Syntax.FunctionParameters);

			if (Token ==Token.RPAREN)
				return tree;

		Next:

			if (Token == Token.CONST)
			{
				tree.Append(Token);
			}

			if (Token == Token.TYPENAME || Token == Token.IDENT)
				tree.Append(Token); // ここで指定されたIDENTはtypenameなのだが。

			while (true)
			{
				switch(Token)
				{
					case Token.MUL:
					case Token.AND:
						tree.Append(Token);
						break;

					default:
						goto Skip;
				}
			}
		Skip:
			tree.Append(Token.IDENT); // ident

			if (Token == Token.COMMA)
			{
				tree.Append(Token);
				goto Next;
			}

			return tree;
		}

		public SyntaxTree Statement()
		{
			// [ assignment; | ProcedureCall; | IfStatement | WhileStatement | ForeachStatement | UnrollStatement |
			// SwitchStatement | AvoidStatemenet | break ]

			var tree = CreateSyntaxTree(Syntax.Statement);

			var token = Token;
			switch (token)
			{
				case Token.IF:
					tree.Append(IfStatement());
					break;

				case Token.WHILE:
					tree.Append(WhileStatement());
					break;

				case Token.FOREACH:
					tree.Append(ForeachStatement());
					break;

				case Token.UNROLL:
					tree.Append(UnrollStatement());
					break;

				case Token.SWITCH:
					tree.Append(SwitchStatement());
					break;

				case Token.FOR:
					tree.Append(ForStatement());
					break;

				case Token.AVOID:
					tree.Append(AvoidStatement());
					break;

				case Token.BREAK:
					tree.Append(Token);
					tree.Append(Token.SEMICOLON); // ";"
					break;

				case Token.CLOSURE:
					tree.Append(Closure());
					break;

				case Token.IDENT:
				case Token.INCREMENT:
				case Token.DECREMENT:
				case Token.TYPENAME:
					{
						// assignment or ProcedureCall
						// ProcedureCall := ident "(" ActualParameters ")"
						// ActualParameters := "("［expression{ "," expression} ］")"．
						// assignment = ident selector "=" expression.

						// 関数テーブルによる関数呼び出しがあるので、
						// C/C++の文法だと型が確定しないと関数呼び出しかどうかは判定できない。
						// しかし関数テーブルによる関数呼び出しは行なわないと仮定する。

						string typename = "";
						if (Token == Token.TYPENAME)
						{
							typename = Ident;
							RemoveToken();
						}

						string id = Ident;

						bool removed = false;

						// 次に"("が来るならProcedureCallだとわかる。
						if (Token == Token.IDENT) 
						{
							RemoveToken();
							removed = true;

							// closureのcallなのか？ 1パラメータの場合だけ以下のように展開する。
							if (closures.ContainsKey(id) && closures[id].elms[3].elms.Count == 1)
							{
								// statement sequenceが来る。
								var ss = StatementSequence();
								// このうち、マクロ名が置換される。

								var macroName = closures[id].elms[3].ToString();
								var closureBody = closures[id].elms[5].ToString();
								var ss_string = closureBody.Replace(macroName, ss.ToString());

								tree.Append(Token.SOMETHING, ss_string);
								// この場合、セミコロン不要

								break;
							}

							// もう一つIDENTが来るなら、ひとつ前のはtypenameだとわかる。
							if (typename == "" && Token == Token.IDENT)
							{
								typename = id;
								id = Ident;
							}
						}
						
						if (Token == Token.LPAREN && typename=="")
						{
							// ProcedureCall

							var tree2 = CreateSyntaxTree(Syntax.ProcedureCall);
							tree2.Append(token, id); // 関数名
							tree2.Append(Token.LPAREN); // "("
							tree2.Append(ActualParameters());
							tree2.Append(Token.RPAREN); // ")"

							tree.Append(tree2);
						}
						else
						{
							// Assignment
							var tree2 = CreateSyntaxTree(Syntax.Assignment);
							if (typename != "")
								tree2.Append(Token.TYPENAME, typename);

							bool isFirst = true;
							Next:

							// 前置increment
							if ((Token == Token.INCREMENT || Token == Token.DECREMENT) && !removed)
							{
								tree2.Append(Token);
								if (Token != Token.IDENT)
								{
									throw new UnrollerException("++/--のあとにindentが来ていない");
								}
								id = Ident;
							} else
							{
								removed = false;
							}
							if (isFirst)
							{
								isFirst = false;
								tree2.Append(Token.IDENT, id); // 代入式の左辺か
							}
							else
							{
								if (Token != Token.IDENT)
									goto End; // ";"か

								tree2.Append(Token);					
							}

							var t = Selector();
							if (t != null)
								tree2.Append(t);

							// 後置increment
							if (Token == Token.INCREMENT || Token == Token.DECREMENT)
								tree2.Append(Token);

							if (Token == Token.SEMICOLON)
							{
								// "p++;" みたいなの
							}
							else
							{

								// '=' , '&=' , '|=' , '+=' , '-=' , ";"
								tree2.Append(
									t1 => t1 == Token.EQUAL || (Token.AND_EQUAL <= t1 && t1 <= Token.MINUS_EQUAL)
									);
								tree2.Append(Expression());
								// まだ代入が続くかも
								goto Next;
							}
						End:
							tree.Append(tree2);
						}
						tree.Append(Token.SEMICOLON); // ";"
					}
					break;
			}
			return tree;
		}

		public SyntaxTree ForStatement()
		{
		//	ForStatement,			// "for" "(" statement expression ";" expression ")" StatementSequence.
			var tree = CreateSyntaxTree(Syntax.ForStatement);
			tree.Append(Token.FOR);
			tree.Append(Token.LPAREN);
			tree.Append(Statement());
			tree.Append(Expression());
			tree.Append(Token.SEMICOLON);
			tree.Append(Expression());
			tree.Append(Token.RPAREN);
			tree.Append(StatementSequence());

			return tree;
		}

		public SyntaxTree Closure()
		{
			// closure ident "(" Parameters ")" StatementSequence;
			var tree = CreateSyntaxTree(Syntax.Closure);
      
			tree.Append(Token);					// "closure"
			tree.Append(Token.IDENT);
			tree.Append(Token.LPAREN);	// "("
			tree.Append(Parameters());
			tree.Append(Token.RPAREN);	// ")"
			tree.Append(StatementSequence());

			// closuresに登録しておこう。
			try
			{
				closures.Add(tree.elms[1].ident, tree);
			}
			catch
			{
				// local closureは使えないので、同名のものがあってはならない。
				throw new UnrollerException("同名のclosureが既に定義されている");
			}

			// これ、defineに変形してreturnしたほうがいいな

			var treeNew = CreateSyntaxTree(Syntax.Macro);
			var closure = "#define " + tree.elms[1] + "(" +
				tree.elms[3] + ")" + tree.elms[5];
			closure = closure.Replace("\r\n", "\\\r\n"); // 改行記号の直前に '\'を追加。
			closure += "\n"; // 最後に空行が必要
			treeNew.Append(Token.SOMETHING , closure);

			return treeNew;
		}

		// closureの名前→SyntaxTreeへのmap
		public Dictionary<string,SyntaxTree> closures = new Dictionary<string, SyntaxTree>();

		public SyntaxTree Parameters()
		{
			//		Parameters,				// ident { "," ident }
			var tree = CreateSyntaxTree(Syntax.Parameters);

			tree.Append(Token.IDENT);
			while (Token == Token.COMMA)
			{
				tree.Append(Token);				// ","
				tree.Append(Token.IDENT);
			}

			return tree;
		}

		public SyntaxTree AvoidStatement()
		{
			// avoid "..." StatementSequence

			var tree = CreateSyntaxTree(Syntax.Avoid);
			var treeNew = CreateSyntaxTree(Syntax.Macro);
			tree.Append(Token);					// "avoid"
			tree.Append(Token.STRING);	// 文字列
			tree.Append(StatementSequence());

			// STRINGに従って、StatementSequenceを置換する。
			var target = tree.elms[1].ident;
			var sq = tree.elms[2].ToString();

			// targetから両端の '"'を除去して、スペースを空白文字列などに置換して
			// それをもってsqから取り除く。
			var target0 = new StringBuilder();
			for (int i = 1; i < target.Length - 1; ++i )
			{
				char c = target[i];
				if ("[]().+*?\\".IndexOf(c) >= 0)	// 正規表現で使う文字はescapeする
				{
					target0.Append("\\" + c);
				}
				else if (c==' ') // スペースなら、スペース相当の文字列
				{
					target0.Append("[ \\t\\r\\n]*?");
				}
				else if (c=='…')
				{
					target0.Append(".*?");
				} else
				{
					target0.Append(c);
				}
			}
			// 正規表現文字列が出来たので、この文字列を除去する。
			var regex = new Regex(target0.ToString());
			var match = regex.Match(sq);
			if (match.Success)
			{
				int index = match.Index;
				int length = match.Length;

				sq = sq.Remove(index, length);
			}
			treeNew.Append(Token.SOMETHING,sq);

			return treeNew;
		}

		private SyntaxTree CreateSyntaxTree(Syntax syntax)
		{
			return new SyntaxTree(syntax,tokenizer);
		}

		// unroll文はmacro扱い。
		public SyntaxTree UnrollStatement()
		{
			var tree = CreateSyntaxTree(Syntax.Unroll); // 一応、構文解析をする。
			var treeNew = CreateSyntaxTree(Syntax.Macro); // 実際は、変換後のソースを保持する。
      
			tree.Append(Token);				// "unroll"

			var token = Token;
			
			switch(token)
			{
				case Token.CASE:
					{
						/*
					unroll case
					{
						case 1: AAA
						case 2: BBB
						case 4: CCC
					}
				*/
						tree.Append(Token.CASE); // "case"
						tree.Append(Token.LBRACE); // "{"

						var caselist = new List<SyntaxTree>();
						while (Token == Token.CASE || Token == Token.DEFAULT)
						{
							var t = CaseStatement();
							tree.Append(t);
							caselist.Add(t);
						}
						tree.Append(Token.RBRACE); // "}"

						// このあとMacroに変換してそれを返す

						// caselistのなかですべての順列組み合わせ
						int n = caselist.Count;
						for (int i = 1; i <= n; ++i)
						{
							var c = new Combination(n, i);
							var m = Combination.Choose(n, i);
							for (int j = 0; j < m; ++j)
							{
								var e = c.Element(j);

								// これですべての順列組み合わせが得られた。

								treeNew.Append(Token.CASE, "case");
								for (int k = 0; k < e.data.Length; ++k)
								{
									if (k != 0)
										treeNew.Append(Token.PLUS, "+");

									// case 1: case 2: みたいになっていないことを仮定しているので
									// まあここは決め打ちでいいや
									treeNew.Append(Token.IDENT, caselist[(int) e.data[k]].elms[0].elms[1].ToString());
								}
								treeNew.Append(Token.COLON, ":");
								for (int k = 0; k < e.data.Length; ++k)
								{
									treeNew.Append(Token.IDENT, caselist[(int) e.data[k]].elms[1].ToString());
								}
								treeNew.Append(Token.BREAK, "break");
								treeNew.Append(Token.SEMICOLON, ";");
							}
						}

						return treeNew;

					}
				case Token.FOREACH:
					{
						// unroll foreach ident in range_parameters StatementSequence
						tree.Append(Token);	// "foreach"
						tree.Append(Token.IDENT);
						tree.Append(Token.IN);
						tree.Append(RangeParameters());
						tree.Append(StatementSequence());

						// 解析が終わったので並べ替えて出力する。

						var ss = tree.elms[5].ToString();
						var target = tree.elms[2].ToString();

						foreach (var t0 in RangeParameters2Enumerator(tree.elms[4]))
						{
							var ss_string = ss.Replace(target, t0);
							treeNew.Append(Token.SOMETHING, ss_string);
						}

						return treeNew;
					}

				default:
					// それ以外のなんかのunroll
					throw new UnrollerException("使えないunroll");
			}
		}

		public static IEnumerable<string> RangeParameters2Enumerator(SyntaxTree tree)
		{
			for (int i = 0; i < tree.elms.Count;++i )
			{
				var token = tree.elms[i].token;
				switch (token)
				{
					case Token.IDENT:
					case Token.STRING:
						yield return tree.elms[i].ident;
						break;

					case Token.NUMBER:
						var start = tree.elms[i].ident;
						var end = start;
						if (i + 2 < tree.elms.Count && tree.elms[i + 1].token == Token.RANGE)
						{
							end = tree.elms[i + 2].ident;
							i += 2; // 解析位置を2つ分、先まで進めておく。
						}

						int start0, end0;
						try
						{
							start0 = int.Parse(start);
							end0 = int.Parse(end);
						}
						catch
						{
							throw new UnrollerException("RangeParameterで数字が指定されていない。");
						}
						for (int j = start0; j <= end0; ++j)
							yield return j.ToString();

						break;
				}

			}
		}

		public SyntaxTree RangeParameters()
		{
			// (Num[".." Num] | ident | string ) { "," (Num[".."Num] | Ident | string) }
			var tree = CreateSyntaxTree(Syntax.RangeParameters);

			while (true)
			{
				switch (Token)
				{
					case Token.NUMBER:
						{
							tree.Append(Token.NUMBER);
							if (Token == Token.RANGE)
							{
								tree.Append(Token.RANGE);
								tree.Append(Token.NUMBER);
							}
							break;
						}
					case Token.IDENT:
						{
							tree.Append(Token.IDENT);
							break;
						}
					case Token.STRING:
						{
							tree.Append(Token.STRING);
							break;
						}
					default:
						goto BREAK;
				}

				if (Token != Token.COMMA)
					break;

				tree.Append(Token.COMMA);
			}

			BREAK:
			if (tree.elms.Count == 0)
				throw new UnrollerException("range parametersが来ていない。");

			return tree;
		}

		public SyntaxTree SwitchStatement()
		{
			// SwitchStatement, // "switch" "(" expression ")" "{" { CaseStatement } "}".
			var tree = CreateSyntaxTree(Syntax.SwitchStatement);
			tree.Append(Token);					// "switch"
			tree.Append(Token.LPAREN);	// "("
			tree.Append(Expression());
			tree.Append(Token.RPAREN);	// ")"
			tree.Append(Token.LBRACE);	// "{"

			while (Token == Token.CASE || Token == Token.DEFAULT)
				tree.Append(CaseStatement());
      
			tree.Append(Token.RBRACE);	// "}"
			return tree;
		}

		public SyntaxTree CaseStatement()
		{
			// CaseStatement,   // CaseLabelList { StatementSequence }.
			var tree = CreateSyntaxTree(Syntax.CaseStatement);
			tree.Append(CaseLabelList());

			while (true)
			{
				tree.Append(StatementSequence());

				if (Token == Token.RBRACE || Token == Token.CASE || Token == Token.DEFAULT)
					return tree;
			}
		}

		public SyntaxTree CaseLabelList()
		{
			//	CaseLabelList,	 // ("case" expression ":" { "case" expression ":" }) | ("default" ":")

			var tree = CreateSyntaxTree(Syntax.CaseLabelList);

			var token = Token;
			switch (token)
			{
				case Token.CASE :
					{
						Next:

						tree.Append(token);

						// case 3..6 みたいな定数RANGEの場合だけ展開しとくか。
						var exp = Expression();
						if (exp.elms.Count == 3 &&
								exp.elms[1].token == Token.RANGE)
						{
							try
							{
								int start = int.Parse(exp.elms[0].ToString());
								int end = int.Parse(exp.elms[2].ToString());

								for (int i = start; i <= end; ++i)
								{
									if (i != start)
										tree.Append(Token.CASE, "case"); // すでに一つはcaseをappendしているのでそれは除外する
									tree.Append(Token.NUMBER, i.ToString());
									if (i != end) // 最後の ":"を除かないといけない。
										tree.Append(Token.COLON, ":");
								}
							}
							catch
							{
							}
						}
						else
						{
							tree.Append(exp);
						}

						tree.Append(Token.COLON);
						if (Token == Token.CASE)
							goto Next;

						break;
					}

					case Token.DEFAULT:
					{
						tree.Append(token);
						tree.Append(Token.COLON);
						break;
					}

					// 本体が空のswitch
					default:
						break;
			}

			return tree;
		}

		public SyntaxTree StatementSequence()
		{
			// "{" statement { statement } "}"

			var tree = CreateSyntaxTree(Syntax.StatementSequence);

			if (Token == Token.LBRACE)
			{
				tree.Append(Token.LBRACE);
			Next:
				var tree0 = Statement();

				if (tree0.elms.Count == 0)
				{
					// 空文みたいなのでこのあとRBRACEでなければならない。
					goto Last;
				}

				tree.Append(tree0);

				if (Token != Token.RBRACE)
				{
					// もう一個か？
					goto Next;
				}
			Last:
				tree.Append(Token.RBRACE);
			} else
			{
				tree.Append(Statement());
			}

			return tree;
		}

		public SyntaxTree ForeachStatement()
		{
			var tree = CreateSyntaxTree(Syntax.ForeachStatement);

			// foreach {":"ident0} "("{typename} ident1 selector in ident2 selector ")" StatementSequence

			tree.Append(Token.FOREACH);	// FOREACH

			var sel = Selector();
			if (sel!=null)
			{
				tree.Append(sel);
			}

			string typename="",ident0="";

			if (Token == Token.COLON)
			{
				tree.Append(Token.COLON);

				ident0 = Ident;
				tree.Append(Token.IDENT);
			}

			tree.Append(Token.LPAREN);		// "("

			if (Token == Token.TYPENAME)
			{
				typename = Ident;
				tree.Append(Token);	// typename
			}

			string ident1 = Ident;
			tree.Append(Token.IDENT);			// 変数名

			tree.Append(Token.IN);				// in

			sel = Selector();
			if (sel != null)
			{
				tree.Append(sel);
			}

			string ident2 = Ident;
			tree.Append(Token.IDENT);				// IDENT

			tree.Append(Token.RPAREN);			// )

			var sq = StatementSequence();
			tree.Append(sq);

			//		return tree;
			// foreachは解析終わったところで、変形して出力したほうがいいと思う。

			// foreach {":" ident0} {typename} ident1 selector in ident2(←enumかなんか) statementsequence
      // ↓
			// typename ident1;
			// foreach_XX(ident2,ident1,{ statementsequence });
			// と変形する。
			// XXの部分はident2が XX_YYY となっていればこのアンダースコアの前の部分を持ってくる。
			// そうでなければ enum なので、foreach_enum にする。
			// ident0が指定されていればXX=ident0
			
			var treeNew = CreateSyntaxTree(Syntax.Macro);

			string type = ident0;

			treeNew.Append(Token.LBRACE,"{");

			if (typename != "")
			{
				// 変数宣言しないと。
				treeNew.Append(Token.TYPENAME,typename);
				treeNew.Append(Token.IDENT,ident1);
				treeNew.Append(Token.SEMICOLON,";");
			}

			// 型名が指定されていないのでindent2から拾ってくる。
			if (type == "")
			{
				int p = ident2.IndexOf('_');
				if (p >= 0)
				{
					type = ident2.Substring(0, p);
				}

				// 型名がないなら、integer
				if (type == "")
					type = "integer";
			}

			treeNew.Append(Token.IDENT, "foreach_" + type + '('
				+ ident2 + ',' + ident1 + ", {" + sq + "});");

			treeNew.Append(Token.RBRACE, "}");

			return treeNew;
		}

		// 関数呼び出しのパラメータ
		public SyntaxTree ActualParameters()
		{
			// { expression { "," expression } }
			var tree = CreateSyntaxTree(Syntax.ActualParameters);

			while (true)
			{
				if (Token == Token.RPAREN) // 空のパラメータ
					break;

				tree.Append(Expression());

				if (Token != Token.COMMA)
					break;

				tree.Append(Token); // ","
			}

			return tree;
		}

		public SyntaxTree IfStatement()
		{
			// "if" "(" expression ")" StatementSequence [ "else" StatementSequence ].
			var tree = CreateSyntaxTree(Syntax.IfStatement);
			tree.Append(Token.IF);
			tree.Append(Token.LPAREN);
			tree.Append(Expression());
			tree.Append(Token.RPAREN);
			tree.Append(StatementSequence());
			if (Token == Token.ELSE)
			{
				tree.Append(Token);
				tree.Append(StatementSequence());
			}

			return tree;
		}
		public SyntaxTree WhileStatement()
		{
			// WhileStatement,		// "while" "(" expression ")" StatementSequence.
			var tree = CreateSyntaxTree(Syntax.WhileStatement);
			tree.Append(Token.WHILE);
			tree.Append(Token.LPAREN);
			tree.Append(Expression());
			tree.Append(Token.RPAREN);
			tree.Append(StatementSequence());

			return tree;
		}
		

		/// <summary>
		/// 式を解析する。
		/// </summary>
		/// <returns></returns>
		public SyntaxTree Expression()
		{
			// SimpleExpression [ ("=" | "<" | "<=" | ">" | ">=" | "..") SimpleExpression].
			//                        ↑三項演算子もここで解析してしまう。
			// SimpleExpression ["?" SimpleExpression ":" SimpleExpression] .

			var tree = CreateSyntaxTree(Syntax.Expression);
			tree.Append(SimpleExpression());

			while (true)
			{
				switch (Token)
				{
					case Token.EQUAL:
					case Token.LT:
					case Token.LE:
					case Token.GT:
					case Token.GE:
					case Token.RANGE:
						{
							tree.Append(Token);
							tree.Append(SimpleExpression());
							break;
						}

					case Token.QUERY:
						{
							tree.Append(Token);
							tree.Append(SimpleExpression());
							tree.Append(Token.COLON);
							tree.Append(SimpleExpression());
							break;
						}

					default:
						return tree;
				}
			}
		}

		public SyntaxTree SimpleExpression()
		{
			// SimpleExpression = ["+" | "-" ] term { ("+" | "-" | "|" | "||" | "^" ) term}.
			// ["+" | "-"] term { AddOperator term }

			var tree = CreateSyntaxTree(Syntax.SimpleExpression);

			if (Token == Token.PLUS || Token == Token.MINUS)
			{
				tree.Append(Token);
			}

			tree.Append(Term());


			while (true)
			{
				switch ( Token )
				{
					case Token.PLUS:
					case Token.MINUS:
					case Token.OR:
					case Token.LOGIC_OR:
					case Token.XOR:
						{
							tree.Append(Token);
							tree.Append(Term());
							break;
						}

					default:
						return tree;
				}
			}

		}

		public SyntaxTree Term()
		{
			// Term,				// factor { MulOperator factor}.

			var tree = CreateSyntaxTree(Syntax.Term);
			tree.Append(Factor());

			Next:

			var token = Token;
			//     MulOperator, // "*" | "/" | "%" | "&" | "&&".
			if (token == Token.MUL || token == Token.DIV ||
				token == Token.PERCENT || token == Token.AND || token == Token.LOGIC_AND
				)
			{
				tree.Append(token);
				tree.Append(Factor());

				goto Next;
			}
			return tree;
		}

		public SyntaxTree Factor()
		{
			// number | CharConstant | ["++" | "--"] ident selector ["++" | "--"]
			//| "(" expression ")" | ("~"|"!") factor.

			var tree = CreateSyntaxTree(Syntax.Factor);
			var token = Token;
			switch (token)
			{
				case Token.STRING:
					{
						tree.Append(Token);
						break;
					}
				case Token.LPAREN:
					{
						tree.Append(Token.LPAREN);
						tree.Append(Expression());
						tree.Append(Token.RPAREN);
						break;
					}
				case Token.LOGIC_NOT:
				case Token.NOT:
					{
						tree.Append(Token);
						tree.Append(Factor());
						break;
					}
				case Token.IDENT:
				case Token.INCREMENT:
				case Token.DECREMENT:
					{
						// 前置increment
						if (Token == Token.INCREMENT || Token == Token.DECREMENT)
							tree.Append(Token);

						tree.Append(Token.IDENT);
						var t = Selector();
						if (t != null)
							tree.Append(t);

						// 後置increment
						if (Token == Token.INCREMENT || Token == Token.DECREMENT)
							tree.Append(Token);

						break;
					}
				case Token.NUMBER:
					{
						tree.Append(Token.NUMBER);
						break;
					}
				default:
					throw new UnrollerException("Factorが来ていない。");
			}

			return tree;
		}

		public SyntaxTree Selector()
		{
			// Selector = {"." ident | "[" expression "]" }.
			// InitExpressionの場合は、この中央のexpressionって省略できるのだが..
			// 省略可能なようにしておくか。

			var tree = CreateSyntaxTree(Syntax.Selector);

			while (true)
			{
				var token = Token;
				if (token == Token.PERIOD)
				{
					tree.Append(Token.PERIOD);
					tree.Append(Token.IDENT);

				} else if (token == Token.LBRACKET) {

					tree.Append(Token.LBRACKET);
					if (Token != Token.RBRACKET)
						tree.Append(Expression());
					tree.Append(Token.RBRACKET);
				} else {
					if (tree.elms.Count == 0)
						return null; // 何もAppendされていない。

					return tree;
				}
			}
		}
	}

	/// <summary>
	/// Unrollerで解析中に出る例外
	/// </summary>
	public class UnrollerException : Exception
	{
		public UnrollerException(string error) : base(error){}
	}

	/// <summary>
	/// Tokenが条件に該当するかどうかを判定する関数。
	/// </summary>
	/// <param name="token"></param>
	/// <returns></returns>
	public delegate bool TokenToBool(Token token);
	
	/// <summary>
	/// 解析で使うための構文木
	/// </summary>
	public class SyntaxTree
	{
		public SyntaxTree(Syntax syntax_ , Tokenizer tk)
		{
			this.syntax = syntax_;
			this.tokenizer = tk;
		}

		/// <summary>
		/// この構文木の末尾にtokenとその文字列を追加
		/// TokenのRemoveはしないので要注意。
		/// </summary>
		public void Append(Token token_,string ident_)
		{
			var tree = new SyntaxTree(Syntax.Token , tokenizer){token = token_, ident = ident_};

			elms.Add(tree);
			tokenizer.PeekToken();
		}

		/// <summary>
		/// この構文木の末尾に構文木を追加する。
		/// </summary>
		/// <param name="tree"></param>
		public void Append(SyntaxTree tree)
		{
			elms.Add(tree);
			tokenizer.PeekToken();
		}

		/// <summary>
		/// 指定したTokenが来ていないといけない場合、それを
		/// チェックして、そのtokenが来ていなければ例外を出す。
		/// 来ていれば、それをRemoveしてtreeにAppendする。
		/// </summary>
		/// <param name="?"></param>
		public void Append(Token t1)
		{
			var t2 = tokenizer.PeekToken();
			if (t1 != t2)
			{
				throw new UnrollerException("token : " + t1 + "が来ずに" + t2 + "が来ている。");
			}
			Append(t1, tokenizer.Ident);
			tokenizer.GetToken(); // Removeして

			tokenizer.PeekToken();	// 次のtokenを読み込んでおく。
		}

				/// <summary>
		/// 指定したTokenが来ていないといけない場合、それを
		/// チェックして、そのtokenが来ていなければ例外を出す。
		/// 来ていれば、それをRemoveしてtreeにAppendする。
		/// </summary>
		/// <param name="?"></param>
		public void Append(TokenToBool tb)
		{
			var t = tokenizer.PeekToken();
			if (! tb(t))
			{
				throw new UnrollerException("必要なtokenが来ていない。");
			}
			Append(t, tokenizer.Ident);
			tokenizer.GetToken();		// ひとつ取り除く

			tokenizer.PeekToken();	// 次のtokenを読み込んでおく。
		}

		/// <summary>
		/// この木の意味するソース文字列を得る。
		/// </summary>
		/// <returns></returns>
		public StringBuilder ToStringBuilder()
		{
			if (syntax == Syntax.Token)
				return new StringBuilder(ident);

			var sb = new StringBuilder();
			foreach(var tree in elms)
			{
				// 一文字前がスペースでなくて行頭でないならスペースを追記する。
				if (sb.Length != 0 && sb[sb.Length - 1] != ' ' && sb[sb.Length - 1] != '\n')
				{
					sb.Append(' ');
				}

				sb.Append(tree.ToStringBuilder());

				if (tree.syntax == Syntax.Token && (
					// ; のあとと、 { }のあとは改行を入れておくと読みやすい。
					tree.token == Token.SEMICOLON || 
					tree.token == Token.RBRACE ||
					tree.token == Token.LBRACE
					))
					sb.Append("\r\n");

				//else
				//  sb.Append(' ');
			}
			return sb;
		}

		/// <summary>
		/// parseしたソースを文字列化する。元のソースっぽいものが出てくる。
		/// </summary>
		/// <returns></returns>
		public override string ToString()
		{
			return ToStringBuilder().ToString();
		}

		// 構文木の内容がわかるように文字列化
		public StringBuilder ToTreeStringBuilder()
		{
			var sb = new StringBuilder();
			foreach (var tree in elms)
			{
				if (tree.syntax == Syntax.Token)
					sb.Append(tree.ident);
				else
				{
					sb.Append('[' + tree.syntax.ToString() + ':');
					sb.Append(tree.ToTreeStringBuilder());
					sb.Append(']');
				}
			}
			return sb;
		}

		public string ToTreeString()
		{
			return ToTreeStringBuilder().ToString();
		}

		// この構文木自体の文法要素
		public Syntax syntax;

		// syntax == Syntax.Tokenのときは↓これが有効
		public Token token;
		public string ident;
	
		// この構文木の各要素
		public List<SyntaxTree> elms = new List<SyntaxTree>();
		private readonly Tokenizer tokenizer;

	
	}

	/// <summary>
	/// 構文解析で用いる
	/// </summary>
	public enum Syntax
	{
		NullSyntax, // 無効なSyntax
		Token,			// 以下の構文要素ではなく、Tokenである。

		Ident ,		// letter { letter | digit }.
		Number,		// digit { digit }.

		// "[ ]" は省略可  "|"は選択  "{ }"は0回以上

		Statement,				// [ assignment | ProcedureCall | IfStatement | WhileStatement | ForeachStatement ] ";"
		StatementSequence,// "{" statement { statement } "}".
		Expression,				// SimpleExpression [("=" | "<" | ... ) SimpleExpression].
		SimpleExpression,	// ["+" | "-"] term { AddOperator term }.
		Term,							// factor { MulOperator factor}.
		Factor,						// number | CharConstant | ["++" | "--"] ident selector ["++" | "--"] | "(" expression ")" | "~" factor.
    MulOperator,			// "*" | "/" | "%" | "&" | "&&".
		AddOperator,			// "+" | "-" | "|" | "||".
		ProcedureCall,		// ident "(" ActualParameters ")"
		ActualParameters, // "("［expression{ "," expression} ］")"．
		Assignment,				// ["++" | "--"] ident selector ["++" | "--"] ("=" | "+=" | ...)  expression.
		Selector,					// {"." ident | "[" expression "]" }.
		SwitchStatement,	// "switch" "(" expression ")" "{" CaseStatement. "}"
		CaseStatement,		// CaseLabelList { StatementSequence } .
		CaseLabelList,		// ("case" expression ":" { "case" expression ":" }) | ("default" ":")
		ForStatement,			// "for" "(" expression ";" expression ";" expression ")" StatementSequence.
		WhileStatement,		// "while" "(" expression ")" StatementSequence.
		IfStatement,			// "if" "(" expression ")" StatementSequence [ "else" StatementSequence ].
		Function,					// typename funcname "(" FunctionParameters ")" StatementSequence.
		FunctionParameters,// { ["const"] typename ["*" | "&"] ident } { "," ["const"] typename ["*" | "&"] ident }
		Program,					// { [ Function | FunctionDeclare | VariableDeclare | Include | Define ] }.
//		Arithmeticif,			// condition ? expression : expression
											// ↑expressionにしておくか。AddOperatorのほうで解析してしまう。
		VariableDeclare,	// typename ident "=" InitExpression.
		InitExpression,		// Expression | "{" {InitExpression {"," InitExpression } "}".

		// --- 以下、独自に追加したもの。
		ForeachStatement,	// foreach{":"ident} "(" {typename} ident selector in ident selector ")" StatementSequence
		Unroll,						// unroll case { CaseStatement }.
		Macro,						// defineなどの塊。foreachを変換したものなど。
		Avoid,						// avoid string StatementSequence.
		Closure,					// closure ident "(" Parameters ")" StatementSequence;

		// closureのパラメータ
		Parameters,				// ident { "," ident }

		// unroll foreachで用いる範囲型
		RangeParameters,	// (Num | ident) { "," (Num | Ident ) }

	}

	/// <summary>
	///  Unrollerで用いるTokenizer
	/// </summary>
	public class Tokenizer
	{
		// プログラムをセットする。そのあと
		// GetTokenでトークンをひとつずつ取り出せる。
		public void SetProgram(string program_)
		{
			this.program = program_;
			Line = 1;
			pos = 0;
			token_buffer = Token.NULL_TOKEN;
			token_last = Token.NULL_TOKEN;
		}

		/// <summary>
		/// Tokenを差し戻すときのbuffer
		/// </summary>
		private Token token_buffer;

		/// <summary>
		/// 最後にGetTokenで返したtoken
		/// </summary>
		private Token token_last;

		/// <summary>
		/// Tokenを差し戻す
		/// </summary>
		public void BackToken()
		{
			if (token_last == Token.NULL_TOKEN)
				throw new Exception("BackTokenで差し戻すtokenが無い");
			token_buffer = token_last;
			token_last = Token.NULL_TOKEN;
		}

		/// <summary>
		/// 次のtokenを覗き見る。取り除きはしない。
		/// </summary>
		/// <returns></returns>
		public Token PeekToken()
		{
			var token = GetToken();
			BackToken();

			return token;
		}

		/// <summary>
		/// SetProgramで設定したプログラムに対して
		/// Tokenをひとつ取得する。
		/// 
		/// 解析位置は自動的に進む。
		/// 
		/// 解析終了まで行くとToken.EOFが返る。
		/// </summary>
		/// <returns></returns>
		public Token GetToken()
		{
			if (token_buffer != Token.NULL_TOKEN)
			{
				token_last = token_buffer;
				Token ret = token_buffer;
				token_buffer = Token.NULL_TOKEN;

				return ret;
			}

			Token token = GetToken_();

			token_last = token;
			return token;
		}

		/// <summary>
		/// SetProgramで設定したプログラムに対して
		/// Tokenをひとつ取得する。
		/// 
		/// 解析位置は自動的に進む。
		/// 
		/// 解析終了まで行くとToken.EOFが返る。
		/// </summary>
		/// <returns></returns>
		private Token GetToken_()
		{
		Retry:

			if (!(pos < program.Length))
			{
				Ident = "";
				return Token.EOF;
			}

			char c = program[pos++];

			// specialCharまで読んでいく。
			const string specialCharSpace = " \t\r\n";

			// スペース、タブは読み捨てる。
			if (specialCharSpace.IndexOf(c) >= 0)
			{
				// ソースコンバータなので読み捨てていいのか？(´ω｀)

				if (c=='\n')
					Line++; // 現在の解析行をインクリメント

				goto Retry;
			}

			// '//' , '/*' ～ '*/'を読み飛ばす
			if (pos < program.Length && c == '/')
			{
				char c1 = program[pos];
				if (c1 == '/')
				{
					// 行末まで飛ばす。
					pos++;
					while (true)
					{
						char c2 = program[pos++];
						if (c2 == '\n')
							goto Retry;
						if (pos == program.Length)
						{
							Ident = "";
							return Token.EOF;
						}
					}
				}
				if (c1 == '*')
				{
					// '*/'まで飛ばす					
					pos++;
					while (true)
					{
						char c2 = program[pos++];
						if (c2 == '*' || program[pos] == '/')
						{
							pos++;
							goto Retry;
						}
						// このあとposの地点から読み出せる文字が2文字なければいけない。
						if (!(pos < program.Length - 2))
						{
							Ident = "";
							return Token.EOF;
						}
					}
				}
			}

			// 2文字tokenか？
			if (pos < program.Length)
			{
				char c1 = program[pos];

				var Token2char = new[]
				{
					"&&" , "||" , "<=" , ">=" , "++" , "--" , ".." , "&=" , "|=" , "+=" , "-=",
				};

				for (int i = 0; i < Token2char.Length;++i )
				{
					if (c == Token2char[i][0] && c1 == Token2char[i][1])
					{
						pos++;
						Ident = Token2char[i];
						return (Token.LOGIC_AND + i);
					}
				}
			}

			// stringか？
			if (c=='"')
			{
				var s = new StringBuilder();
				s.Append(c);
				
				// 閉じ '"' まで

				int l = Line;
				while (true)
				{
					if (!(pos < program.Length))
					{
						throw new UnrollerException(l + "行目の\"が閉じずに終わりまで到達した。");
					}
					c = program[pos++];
					s.Append(c);
					if (c == '"')
						break;
				}

				Ident = s.ToString();
				return Token.STRING;
			}


			const string specialChar = "+-*/()[]{}:;.,!?|&^%=<>~";

			// 1文字記号か？
			{
				int n = specialChar.IndexOf(c);
				if (n >= 0)
				{
					Ident = c.ToString();
					return Token.PLUS + n;
				}
			}
			
			// 数字で始まるなら、アルファベットまでがtokenだが、
			// 数字 + アルファベットという使い方はしないため、
			// まあ普通にparseして良い。

			{
				var sb = new StringBuilder();
				while (true)
				{
					sb.Append(c);
					c = program[pos];
					if (specialChar.IndexOf(c) >= 0 || specialCharSpace.IndexOf(c) >= 0)
					{
						Ident = sb.ToString();
						break;
					}
					pos++;
					if (pos == program.Length)
					{
						sb.Append(c);
						Ident = sb.ToString();
						break;
					}
				}
			}

			// 命令
			var Commands = new[]
			{
				"if","else","switch","case","default","do","while","for","break","const",
        "foreach","in","unroll","avoid","closure",
			};

			for (int i = 0; i < Commands.Length;++i )
				if (Ident == Commands[i])
				{
					Ident = Commands[i];
					return Token.IF + i;
				}
			
			// 型名 : int,u8,s8,u16,s16,u32,s32,u64,s64

			var typeNames = new[]
			{
        "void","int","u8","s8","u16","s16","u32","s32","u64","s64",
				// 使いそうな型名を↓に書いておくと便利。
        "Result","BitBoard","DBB","BoardPos","Move"
			};

			for (int i = 0; i < typeNames.Length; ++i)
				if (Ident == typeNames[i])
				{
					Ident = typeNames[i];
					return Token.TYPENAME;
				}

			for (int i = 0; i < TypeNames.Count; ++i )
				if (Ident == TypeNames[i])
				{
					Ident = TypeNames[i];
					return Token.TYPENAME;
				}

				// 数字か？
				if (Ident.Length != 0 && ('0' <= Ident[0] && Ident[0] <= '9'))
				{
					// 数字ではじまっちょるから数字でいいよな..途中で文字がまじってるかも知れんが..
					// "0xABCD"とかもあるし。
					return Token.NUMBER;
				}

			// それ以外
			return Token.IDENT;
		}

		/// <summary>
		/// GetTokenでToken.IDENTが返ったときはここにその命令が入っている。
		/// それ以外の場合も読み込まれた元のtoken文字列が入っている。
		/// Token.Numberの場合もここにその文字列が入る。
		/// </summary>
		public string Ident
		{ get; private set;}

		/// <summary>
		/// parseするプログラム
		/// </summary>
		private string program { get; set; }

		/// <summary>
		/// ↑のProgramの現在の解析位置
		/// </summary>
		private int pos;

		// 現在の解析行。
		public int Line { get; private set; }

		// 型名。自分で使う型名を登録しておくといいかも。
		public List<string> TypeNames = new List<string>();
	}

	/// <summary>
	/// Unrollerで用いるparserで用いるToken
	/// </summary>
  public enum Token
  {
		NULL_TOKEN, // 無効なtoken
		EOF,				// 終了

		IDENT,		// それ以外の識別子
    NUMBER,		// 数字
		TYPENAME, // 型名 : int,u8,s8,u16,s16,u32,s32,u64,s64
		STRING,		// " "で囲まれた文字列。IDENTは、その文字列が入る。このときIDENTには両端の '"' も含まれる。

		// ' 'と" "
		QUOTE,
		DQUOTE,		// 実際はSTRINGが返るから、これは使わない。

		// 2文字記号
		// "&&" , "||" , "<=" , ">=" , "++" , "--" , ".." , "&=" , "|=" , "+=" , "-="
		LOGIC_AND,
		LOGIC_OR,
		LE,
		GE,
		INCREMENT,
		DECREMENT,
		RANGE,
		AND_EQUAL,
		OR_EQUAL,
		PLUS_EQUAL,
		MINUS_EQUAL,

		// 1文字記号
		// +-*/()[]{}:;.,!?|&^%=<>~
		PLUS,
		MINUS,
		MUL,
		DIV,
		LPAREN,			// (
		RPAREN,			// )
    LBRACKET,		// [
		RBRACKET,		// ]
		LBRACE,			// {
		RBRACE,			// }
		COLON,
		SEMICOLON,
		PERIOD,
		COMMA,
		LOGIC_NOT,	// !
		QUERY,
		OR,
		AND,
		XOR,
		PERCENT,
		EQUAL,
		LT,
		GT,
		NOT,				// ~

		// 以下、予約語
		IF,
		ELSE,
		SWITCH,
		CASE,
		DEFAULT,
		DO,
		WHILE,
		FOR,
		BREAK,
		CONST,

		// 以下この言語用に追加した命令
		FOREACH,
		IN,
		UNROLL,
		AVOID,
		CLOSURE,

		// SyntaxTreeを何らかの置換をしたときに何かToken名が必要になるときはこれになっている。
		SOMETHING,
	}


	// http://msdn.microsoft.com/ja-jp/library/cc404918(VS.71).aspx?ppud=4
	public class Combination
	{
		private long n = 0;
		private long k = 0;
		public long[] data = null; // こいつに直接アクセスしたいので、これpublicにしとく(yane)

		public Combination(long n, long k)
		{
			if (n < 0 || k < 0) // 通常は n >= k
				throw new Exception("コンストラクタのパラメータが負の数です");

			this.n = n;
			this.k = k;
			this.data = new long[k];
			for (long i = 0; i < k; ++i)
				this.data[i] = i;
		} // Combination(n,k)

		public Combination(long n, long k, long[] a) // a[] の組み合わせ
		{
			if (k != a.Length)
				throw new Exception("配列の長さが k に等しくありません");

			this.n = n;
			this.k = k;
			this.data = new long[k];
			for (long i = 0; i < a.Length; ++i)
				this.data[i] = a[i];

			if (!this.IsValid())
				throw new Exception("配列の値が正しくありません");
		} // (n,k,a) の組み合わせ

		public bool IsValid()
		{
			if (this.data.Length != this.k)
				return false; // 破損

			for (long i = 0; i < this.k; ++i)
			{
				if (this.data[i] < 0 || this.data[i] > this.n - 1)
					return false; // 範囲外の値

				for (long j = i + 1; j < this.k; ++j)
					if (this.data[i] >= this.data[j])
						return false; // 重複しているか、辞書式でない
			}

			return true;
		} // IsValid()

		public override string ToString()
		{
			string s = "{ ";
			for (long i = 0; i < this.k; ++i)
				s += this.data[i].ToString() + " ";
			s += "}";
			return s;
		} // ToString()

		public Combination Successor()
		{
			if (this.data[0] == this.n - this.k)
				return null;

			Combination ans = new Combination(this.n, this.k);

			long i;
			for (i = 0; i < this.k; ++i)
				ans.data[i] = this.data[i];

			for (i = this.k - 1; i > 0 && ans.data[i] == this.n - this.k + i; --i)
				;

			++ans.data[i];

			for (long j = i; j < this.k - 1; ++j)
				ans.data[j + 1] = ans.data[j] + 1;

			return ans;
		} // Successor()

		public static long Choose(long n, long k)
		{
			if (n < 0 || k < 0)
				throw new Exception("Choose() の負のパラメータは無効です");
			if (n < k)
				return 0;  // 特殊なケース
			if (n == k)
				return 1;

			long delta, iMax;

			if (k < n - k) // 例: Choose(100,3)
			{
				delta = n - k;
				iMax = k;
			}
			else         // 例: Choose(100,97)
			{
				delta = k;
				iMax = n - k;
			}

			long ans = delta + 1;

			for (long i = 2; i <= iMax; ++i)
			{
				checked { ans = (ans * (delta + i)) / i; }
			}

			return ans;
		} // Choose()

		// 組み合わせ C(n,k) の辞書式順序で m 番目の要素を返します
		public Combination Element(long m)
		{
			long[] ans = new long[this.k];

			long a = this.n;
			long b = this.k;
			long x = (Choose(this.n, this.k) - 1) - m; // x は m の "デュアル"

			for (long i = 0; i < this.k; ++i)
			{
				ans[i] = LargestV(a, b, x); // 最大値は v です。ここで、v < a および vCb < x
				x = x - Choose(ans[i], b);
				a = ans[i];
				b = b - 1;
			}

			for (long i = 0; i < this.k; ++i)
			{
				ans[i] = (n - 1) - ans[i];
			}

			return new Combination(this.n, this.k, ans);
		} // Element()


		// 最大値 v を返します。ここで、v < a および Choose(v,b) <= x
		private static long LargestV(long a, long b, long x)
		{
			long v = a - 1;

			while (Choose(v, b) > x)
				--v;

			return v;
		} // LargestV()

	} // Combination クラス}

}
