
function build( $module )
{
				$sourceBasePath = "E:/d/compo/src/sworks/compo";
				$targetBasePath = "./src/sworks/compo";
				$sourcePath = Join-Path -path $sourceBasePath -childpath $module;
				$targetPath = Join-Path -path $targetBasePath -childpath $module;

				if( -not (Test-Path $sourcePath) ) { throw "the package " + $package + " does not exist."; }
				if( -not (Test-Path (Split-Path $targetPath)) ) `
				{
						New-Item -type directory -name (Split-Path $targetPath);
				}
				Copy-Item -path $sourcePath -destination $targetPath;
}

build( "util/strutil.d" );
build( "util/output.d" );
build( "util/sequential_file.d" );
build( "util/cached_buffer.d" );
build( "win32/sjis.d" );