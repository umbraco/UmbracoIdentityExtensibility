param (
	[Parameter(Mandatory=$true)]
	[ValidatePattern("^\d\.\d\.(?:\d\.\d$|\d$)")]
	[string]
	$ReleaseVersionNumber,
	[Parameter(Mandatory=$true)]
	[string]
	[AllowEmptyString()]
	$PreReleaseName
)

$PSScriptFilePath = (Get-Item $MyInvocation.MyCommand.Path);
$RepoRoot = (get-item $PSScriptFilePath).Directory.Parent.FullName;
$SolutionRoot = Join-Path -Path $RepoRoot "src";

#trace
"Solution Root: $SolutionRoot"

# Make sure we don't have a release folder for this version already
$BuildFolder = Join-Path -Path $RepoRoot -ChildPath "build";
$ReleaseFolder = Join-Path -Path $BuildFolder -ChildPath "Release";
if ((Get-Item $ReleaseFolder -ErrorAction SilentlyContinue) -ne $null)
{
	Write-Warning "$ReleaseFolder already exists on your local machine. It will now be deleted."
	Remove-Item $ReleaseFolder -Recurse
}
New-Item $ReleaseFolder -Type directory

# Go get nuget.exe if we don't hae it
$NuGet = "$BuildFolder\nuget.exe"
$FileExists = Test-Path $NuGet 
If ($FileExists -eq $False) {
	Write-Host "Retrieving nuget.exe..."
	$SourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
	Invoke-WebRequest $SourceNugetExe -OutFile $NuGet
}

# ensure we have vswhere
New-Item "$BuildFolder\vswhere" -type directory -force
$vswhere = "$BuildFolder\vswhere.exe"
if (-not (test-path $vswhere))
{
	Write-Host "Download VsWhere..."
	$path = "$BuildFolder\tmp"
	&$nuget install vswhere -OutputDirectory $path -Verbosity quiet
	$dir = ls "$path\vswhere.*" | sort -property Name -descending | select -first 1
	$file = ls -path "$dir" -name vswhere.exe -recurse
	mv "$dir\$file" $vswhere   
}

$MSBuild = &$vswhere -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | select-object -first 1
if (-not (test-path $MSBuild)) {
	throw "MSBuild not found!"
}

# Set the version number in SolutionInfo.cs
$AssemblyInfoPath = Join-Path -Path $SolutionRoot -ChildPath "Umbraco.IdentityExtensions\Properties\AssemblyInfo.cs"
(gc -Path $AssemblyInfoPath) `
	-replace "(?<=AssemblyFileVersion\(`")[.\d]*(?=`"\))", $ReleaseVersionNumber |
	sc -Path $AssemblyInfoPath -Encoding UTF8;
(gc -Path $AssemblyInfoPath) `
	-replace "(?<=AssemblyInformationalVersion\(`")[.\w-]*(?=`"\))", "$ReleaseVersionNumber$PreReleaseName" |
	sc -Path $AssemblyInfoPath -Encoding UTF8;
# Set the copyright
$Copyright = "Copyright " + [char]0x00A9 + " Umbraco " + (Get-Date).year
(gc -Path $AssemblyInfoPath) `
	-replace "(?<=AssemblyCopyright\(`").*(?=`"\))", $Copyright |
	sc -Path $AssemblyInfoPath -Encoding UTF8;

# Build the solution in release mode
$SolutionPath = Join-Path -Path $SolutionRoot -ChildPath "Umbraco.IdentityExtensions.sln";

# clean sln for all deploys
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount /t:Clean
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}

#build
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}

#Copy DLLs and code files to output dir
$IdentityExtensionsReleaseFolder = Join-Path -Path $ReleaseFolder -ChildPath "Umbraco.IdentityExtensions";
New-Item $IdentityExtensionsReleaseFolder -Type directory
$include = @('Umbraco.IdentityExtensions.dll','Umbraco.IdentityExtensions.pdb')
$ProjFolder = Join-Path -Path $SolutionRoot -ChildPath "Umbraco.IdentityExtensions";
New-Item "$IdentityExtensionsReleaseFolder\bin\" -Type directory
New-Item "$IdentityExtensionsReleaseFolder\App_Start\" -Type directory
Copy-Item "$ProjFolder\bin\Release\*.*" -Destination "$IdentityExtensionsReleaseFolder\bin\" -Include $include
Copy-Item "$ProjFolder\App_Start\*.*" -Destination "$IdentityExtensionsReleaseFolder\App_Start\"
# Replace the namespace with the token in each file
Get-ChildItem "$IdentityExtensionsReleaseFolder\App_Start\" -Recurse -Filter *.pp |
Foreach-Object {
	(Get-Content $_.FullName) `
	-replace " Umbraco.IdentityExtensions.CodeFiles", " `$rootnamespace`$" |
	Set-Content $_.FullName -Encoding UTF8;
}


$AppStartFolder = Join-Path -Path $SolutionRoot -ChildPath "App_Start";
$AppStartDestFolder = Join-Path -Path $ReleaseFolder -ChildPath "App_Start";
Copy-Item "$AppStartFolder\*.*" -Destination (New-Item ($AppStartDestFolder) -Type directory);

# Rename all .cs files to .cs.pp
Get-ChildItem $AppStartDestFolder -Recurse -Filter *.cs | Rename-Item -newname {  $_.name  -Replace '\.cs$','.cs.pp'  }

# COPY THE READMES OVER
Copy-Item "$BuildFolder\*.txt" -Destination $ReleaseFolder

# COPY OVER THE NUSPECS
Copy-Item "$BuildFolder\*.nuspec" -Destination $ReleaseFolder

# BUILD THE NUGET PACKAGES

$NuSpec = Join-Path -Path $ReleaseFolder -ChildPath "UmbracoCms.IdentityExtensions.nuspec";
& $NuGet pack $NuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName

$NuSpec = Join-Path -Path $ReleaseFolder -ChildPath "UmbracoCms.IdentityExtensions.AzureActiveDirectory.nuspec";
& $NuGet pack $NuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName

$NuSpec = Join-Path -Path $ReleaseFolder -ChildPath "UmbracoCms.IdentityExtensions.Google.nuspec";
& $NuGet pack $NuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName

$NuSpec = Join-Path -Path $ReleaseFolder -ChildPath "UmbracoCms.IdentityExtensions.Facebook.nuspec";
& $NuGet pack $NuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName

$NuSpec = Join-Path -Path $ReleaseFolder -ChildPath "UmbracoCms.IdentityExtensions.Microsoft.nuspec";
& $NuGet pack $NuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName

""
"Build $ReleaseVersionNumber$PreReleaseName is done!"

