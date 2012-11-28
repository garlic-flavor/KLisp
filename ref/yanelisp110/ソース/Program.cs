using System;
using System.IO;
using System.Windows.Forms;

namespace YaneLisp
{
	static class Program
	{
		/// <summary>
		/// アプリケーションのメイン エントリ ポイントです。
		/// </summary>
		[STAThread]
		static void Main(string[] args)
		{
			//LispTest.UnitTest();

			bool needHelp = true;
			for (int i = 0; i < args.Length;++i )
			{
				switch (args[i])
				{
					case "-include":
						// 読み込むファイルが指定されている。
						eval(args[i + 1],true);
						needHelp = false;
						++i;
						break;

					case "-import":
						// 読み込むファイルが指定されている。
						eval(args[i + 1],false);
						needHelp = false;
						++i;
						break;

					case "-test":
						// UnitTest
						LispTest.UnitTest();
						needHelp = false;
						break;

					// http://d.hatena.ne.jp/ak11/20091122 のpatch
					case "-compile":
						try
						{
							string filename = args[++i];
							string output = args[++i];
							// 出力ファイルよりソースファイルが新しい時のみ処理
							if (!File.Exists(output) ||
							    File.GetLastWriteTime(output) < File.GetLastWriteTime(filename))
							{
								Console.WriteLine(filename + " => " + output);
								var lisp = new Lisp();
								lisp.setVar("outfile", new SExp {elms = output});
								SExp ret = lisp.eval(new ConvSExp().import(filename));
							//	Console.WriteLine(lisp.SExp2string(ret));
							}
						}
						catch (Exception ex)
						{
							Console.WriteLine(ex.ToString());
						}
						needHelp = false;
						break;


					case "-help":
					case "-h":
						Help();
						needHelp = false;
						break;
				}
			}

			if (needHelp)
			{
				Help();
			}
		}

		static void Help()
		{
			Console.WriteLine("YaneLisp version 1.10  programmed by yaneurao 2009");
			Console.WriteLine("-h , -help : このヘルプを表示。");
			Console.WriteLine("-test      : UnitTestの実行。");
			Console.WriteLine("-include [filename] : 実行するファイルを指定。");
			Console.WriteLine("-import [filename] : 実行するファイルを指定。//% が実行する行。");
			Console.WriteLine("-compile [source_filename] [dest_filename] : 実行するファイルを指定。//% が実行する行。");
			Console.WriteLine("何も指定がないときは、-include lisp.txt が指定されたことになる。");
		}

		static void eval(string filename,bool isInclude)
		{
			try {
				var exp = (isInclude) ? new ConvSExp().include(filename) : new ConvSExp().import(filename);
				var ret = LispUtil.eval(exp);
				Console.WriteLine(ret);
			}
			catch (Exception ex)
			{
				Console.WriteLine(ex.Message);
			}
		}
	}
}
