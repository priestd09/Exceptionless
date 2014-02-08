# Copyright 2014 Exceptionless
#
# This program is free software: you can redistribute it and/or modify it 
# under the terms of the GNU Affero General Public License as published 
# by the Free Software Foundation, either version 3 of the License, or 
# (at your option) any later version.
# 
#     http://www.gnu.org/licenses/agpl-3.0.html

Framework "4.5.1"

properties {
    $version =  "1.3"
    $configuration = "Release"

    $base_dir = Resolve-Path "."
    $source_dir = "$base_dir\Source"
    $lib_dir = "$base_dir\Libraries"
    $build_dir = "$base_dir\Build"
    $working_dir = "$build_dir\Working"
    $deploy_dir = "$build_dir\Deploy"
    $packages_dir = "$base_dir\Packages"

    $sln_file = "$base_dir\Exceptionless.NoSamples.sln"
    $sign_file = "$source_dir\Exceptionless.snk"

    $client_projects = @(
        @{ Name = "Exceptionless"; 			SourceDir = "$source_dir\Clients\Shared";	ExternalNuGetDependencies = $null;	MergeDependencies = "Exceptionless.Models.dll;"; },
        @{ Name = "Exceptionless.Mvc";  	SourceDir = "$source_dir\Clients\Mvc"; 		ExternalNuGetDependencies = $null;	MergeDependencies = $null; },
        @{ Name = "Exceptionless.WebApi";  	SourceDir = "$source_dir\Clients\WebApi"; 	ExternalNuGetDependencies = $null;	MergeDependencies = $null; },
        @{ Name = "Exceptionless.Web"; 		SourceDir = "$source_dir\Clients\Web"; 		ExternalNuGetDependencies = $null;	MergeDependencies = $null; },
        @{ Name = "Exceptionless.Windows"; 	SourceDir = "$source_dir\Clients\Windows"; 	ExternalNuGetDependencies = $null;	MergeDependencies = $null; },
        @{ Name = "Exceptionless.Wpf"; 		SourceDir = "$source_dir\Clients\Wpf"; 		ExternalNuGetDependencies = $null;	MergeDependencies = $null; }
    )

    $client_build_configurations = @(
        @{ Constants = "PFX_LEGACY_3_5;NET35;EMBEDDED;";	TargetFrameworkVersion = "v3.5"; NuGetDir = "net35"; },
        @{ Constants = "EMBEDDED;NET40;"; 					TargetFrameworkVersion = "v4.0"; NuGetDir = "net40"; },
        @{ Constants = "EMBEDDED;NET45;"; 					TargetFrameworkVersion = "v4.5"; NuGetDir = "net45"; }
    )

    $client_test_projects = @(
        @{ Name = "Exceptionless.Client.Tests";	BuildDir = "$source_dir\Clients\Tests\bin\$configuration"; }
    )

    $server_test_projects = @(
        @{ Name = "Exceptionless.Tests";		BuildDir = "$source_dir\Tests\bin\$configuration"; }
    )
}

Include .\teamcity.ps1

task default -depends Package
task client -depends PackageClient
task server -depends PackageServer

task Clean {
    Delete-Directory $build_dir
}

task Init -depends Clean {
    Verify-BuildRequirements

    if (![string]::IsNullOrWhiteSpace($env:BUILD_NUMBER)) {
        $build_number = $env:BUILD_NUMBER
    } else {
        $build_number = "0"
    }

    if (![string]::IsNullOrWhiteSpace($env:BUILD_VCS_NUMBER_Exceptionless_Master)) {
        $git_hash = $env:BUILD_VCS_NUMBER_Exceptionless_Master.Substring(0, 10)
        TeamCity-ReportBuildProgress "VCS Revision: $git_hash"
    }

    $info_version = "$version.$build_number $git_hash".Trim()
    $script:nuget_version = "$version.$build_number"
    $version = "$version.$build_number"

    TeamCity-SetBuildNumber $version
    
    Update-GlobalAssemblyInfo "$source_dir\GlobalAssemblyInfo.cs" $version $version $info_version
}

task BuildClient -depends Init {			
    ForEach ($p in $client_projects) {
        ForEach ($b in $client_build_configurations) {
            if ((($($p.Name) -eq "Exceptionless.Mvc") -or ($($p.Name) -eq "Exceptionless.WebApi")) -and ($($b.TargetFrameworkVersion) -eq "v3.5")) {
                Continue;
            }
            
            $outputDirectory = "$build_dir\$configuration\$($p.Name)\lib\$($b.NuGetDir)"
            
            TeamCity-ReportBuildStart "Building $($p.Name) ($($b.TargetFrameworkVersion))" 
            exec { & msbuild "$($p.SourceDir)\$($p.Name).csproj" `
                /p:AssemblyOriginatorKeyFile="$sign_file" `
                /p:Configuration="$configuration" `
                /p:Platform="AnyCPU" `
                /p:DefineConstants="`"TRACE;$($b.Constants)`"" `
                /p:OutputPath="$outputDirectory" `
                /p:SignAssembly=true `
                /p:TargetFrameworkVersion="$($b.TargetFrameworkVersion)" `
                /t:"Rebuild" }
            
            TeamCity-ReportBuildFinish "Finished building $($p.Name) ($($b.TargetFrameworkVersion))"
        }
    }

    TeamCity-ReportBuildStart "Building Client Tests" 
    exec { & msbuild "$source_dir\Clients\Tests\Exceptionless.Client.Tests.csproj" `
        /p:Configuration="$configuration" `
        /t:"Rebuild" }
    TeamCity-ReportBuildFinish "Finished building Client Tests"
}

task BuildServer -depends Init {			
    TeamCity-ReportBuildStart "Building Exceptionless" 
    exec { msbuild "$sln_file" /p:Configuration="$configuration" /p:Platform="Any CPU" /t:Rebuild }
    TeamCity-ReportBuildFinish "Finished building Exceptionless"
}

task Build -depends BuildClient, BuildServer

task TestClient -depends BuildClient {
    $failure = $FALSE

    ForEach ($p in $client_test_projects) {
        if (!(Test-Path -Path "$($p.BuildDir)\$($p.Name).dll")) {
            TeamCity-ReportBuildStatus 'FAILURE' "Unit test project $($p.Name) needs to be compiled first."
            return;
        }

        exec { & "$lib_dir\xunit\xunit.console.clr4.exe" "$($p.BuildDir)\$($p.Name).dll"; }
        if ($lastExitCode -ne 0) {
            $failure = $TRUE
            TeamCity-ReportBuildStatus 'FAILURE' "One or more client unit test in project $($p.Name) failed."
        } else {
            TeamCity-ReportBuildStatus 'SUCCESS' "Finished client unit testing project $($p.Name)"
        }
    }

    if ($failure) {
        TeamCity-ReportBuildStatus 'FAILURE' "One or more client unit tests failed."
        Throw "One or more client unit tests failed."
    }
}

task TestServer -depends BuildServer {
    $failure = $FALSE

    ForEach ($p in $server_test_projects) {
        if (!(Test-Path -Path "$($p.BuildDir)\$($p.Name).dll")) {
            TeamCity-ReportBuildStatus 'FAILURE' "Unit test project $($p.Name) needs to be compiled first."
            return;
        }

        exec { & "$lib_dir\xunit\xunit.console.clr4.exe" "$($p.BuildDir)\$($p.Name).dll"; }
        if ($lastExitCode -ne 0) {
            $failure = $TRUE
            TeamCity-ReportBuildStatus 'FAILURE' "One or more server unit test in project $($p.Name) failed."
        } else {
            TeamCity-ReportBuildStatus 'SUCCESS' "Finished server unit testing project $($p.Name)"
        }
    }

    if ($failure) {
        TeamCity-ReportBuildStatus 'FAILURE' "One or more server unit tests failed."
        Throw "One or more server unit tests failed."
    }
}

task Test -depends TestClient, TestServer

task PackageClient -depends TestClient {
    Create-Directory $deploy_dir

    ForEach ($p in $client_projects) {
        $workingDirectory = "$working_dir\$($p.Name)"
        Create-Directory $workingDirectory

        #copy assemblies from build directory to working directory.
        ForEach ($b in $client_build_configurations) {
            if ((($($p.Name) -eq "Exceptionless.Mvc") -or ($($p.Name) -eq "Exceptionless.WebApi")) -and ($($b.TargetFrameworkVersion) -eq "v3.5")) {
                Continue;
            }

            $buildDirectory = "$build_dir\$configuration\$($p.Name)\lib\$($b.NuGetDir)"
            $workingLibDirectory = "$workingDirectory\lib\$($b.NuGetDir)"
            Create-Directory $workingLibDirectory

            #if ($($p.MergeDependencies) -ne $null) {
            #	ILMerge-Assemblies $buildDirectory $workingLibDirectory "$($p.Name).dll" "$($p.MergeDependencies)" "$($b.TargetFrameworkVersion)"
            #} else {
            #	Copy-Item -Path "$buildDirectory\$($p.Name).dll" -Destination $workingLibDirectory
            #}

            # Work around until we are able to merge dependencies and update other project dependencies pre build (E.G., MVC client references Models)
            Copy-Item -Path "$buildDirectory\$($p.Name).dll" -Destination $workingLibDirectory
            if (Test-Path -Path "$buildDirectory\$($p.Name).xml") {
                Copy-Item -Path "$buildDirectory\$($p.Name).xml" -Destination $workingLibDirectory
            }

            if ($($p.MergeDependencies) -ne $null) {
                ForEach ($assembly in $($p.MergeDependencies).Split(";", [StringSplitOptions]"RemoveEmptyEntries")) {
                    Copy-Item -Path "$buildDirectory\$assembly" -Destination $workingLibDirectory
                    if (Test-Path -Path "$buildDirectory\$assembly".Replace(".dll", ".xml")) {
                        Copy-Item -Path "$buildDirectory\$assembly".Replace(".dll", ".xml") -Destination $workingLibDirectory
                    }
                }
            }
        }
        
        if ((Test-Path -Path "$($p.SourceDir)\NuGet")) {
            Copy-Item "$($p.SourceDir)\NuGet\*" $workingDirectory -Recurse
        }

        Copy-Item "$($source_dir)\Clients\LICENSE.txt" $workingDirectory
        Copy-Item "$($source_dir)\Clients\Shared\NuGet\tools\exceptionless.psm1" "$workingDirectory\tools"

        $nuspecFile = "$workingDirectory\$($p.Name).nuspec"
        
        # update NuGet nuspec file.
        if (($($p.ExternalNuGetDependencies) -ne $null) -and (Test-Path -Path "$($p.SourceDir)\packages.config")) {
            $packages = [xml](Get-Content "$($p.SourceDir)\packages.config")
            $nuspec = [xml](Get-Content $nuspecFile)
            
            ForEach ($d in $($p.ExternalNuGetDependencies).Split(";", [StringSplitOptions]"RemoveEmptyEntries")) {
                $package = $packages.SelectSinglenode("/packages/package[@id=""$d""]")
                $nuspec | Select-Xml '//dependency' |% {
                    if($_.Node.Id.Equals($d)){
                        $_.Node.Version = "$($package.version)"
                    }
                }
            }

            $nuspec.Save($nuspecFile);
        }
        
        $packageDir = "$deploy_dir\packages"
        Create-Directory $packageDir

        exec { & $base_dir\.nuget\NuGet.exe pack $nuspecFile -OutputDirectory $packageDir -Version $nuget_version }
    }

    Get-ChildItem -Path "$deploy_dir\packages" -Recurse | ForEach-Object {
        $filename = $_.Directory.ToString() + '\' + $_.Name
        TeamCity-PublishArtifact $filename
    }

    Delete-Directory "$build_dir\$configuration"
    Delete-Directory $working_dir
}

task PackageServer -depends TestServer {
    Create-Directory $deploy_dir

    ZipAndPublishArtifact "$source_dir\Web\" "$deploy_dir\Exceptionless.Web.zip"
    ZipAndPublishArtifact "$source_dir\SchedulerService\" "$deploy_dir\SchedulerService.zip"

    TeamCity-ReportBuildStatus 'SUCCESS' "Success"
}

task Package -depends PackageClient, PackageServer

Function Update-GlobalAssemblyInfo ([string] $filename, [string] $assemblyVersionNumber, [string] $assemblyFileVersionNumber, [string] $assemblyInformationalVersionNumber) {
    $assemblyVersion = "AssemblyVersion(`"$assemblyVersionNumber`")"
    $assemblyFileVersion = "AssemblyFileVersion(`"$assemblyFileVersionNumber`")"
    $assemblyInformationalVersion = "AssemblyInformationalVersion(`"$assemblyInformationalVersionNumber`")"

    TeamCity-ReportBuildProgress "Version: $assemblyVersionNumber Bind Version: $assemblyFileVersionNumber Info Version: $assemblyInformationalVersionNumber"

    (Get-Content $filename) | ForEach-Object {
        % {$_ -replace 'AssemblyVersion\("[^"]+"\)', $assemblyVersion } |
        % {$_ -replace 'AssemblyVersion = "[^"]+"', "AssemblyVersion = `"$assemblyVersionNumber`"" } |
        % {$_ -replace 'AssemblyFileVersion\("[^"]+"\)', $assemblyFileVersion } |
        % {$_ -replace 'AssemblyFileVersion = "[^"]+"', "AssemblyFileVersion = `"$assemblyFileVersionNumber`"" } |
        % {$_ -replace 'AssemblyInformationalVersion\("[^"]+"\)', $assemblyInformationalVersion } |
        % {$_ -replace 'AssemblyInformationalVersion = "[^"]+"', "AssemblyInformationalVersion = `"$assemblyInformationalVersionNumber`"" }
    } | Set-Content $filename
}

Function Verify-BuildRequirements() {
    if ((ls "$env:windir\Microsoft.NET\Framework\v4.0*") -eq $null) {
        throw "Building Exceptionless requires .NET 4.0/4.5, which doesn't appear to be installed on this machine."
    }
}

Function ZipAndPublishArtifact ([string] $sourceDir, [string] $artifactFilePath) {
    Create-Directory $working_dir

    $exclude = @('*.cs', '*.csproj', '*.ide', '*.pdb', '*.resx', '*.settings', '*.suo', '*.user', '*.xsd', 'packages.config' )
    Get-ChildItem $sourceDir -Recurse -Exclude $exclude | ? { $_.FullName -notmatch "\\obj\\?" } | Copy-Item -Destination {Join-Path $working_dir $_.FullName.Substring($sourceDir.length)}

    # Remove empty folders
    Get-ChildItem $working_dir -Recurse | Where {$_.PSIsContainer -and @(Get-ChildItem -Lit $_.Fullname -r | Where {!$_.PSIsContainer}).Length -eq 0} | Remove-Item -Recurse

    Compress-7Zip -ArchiveFileName $artifactFilePath -Path $working_dir -Format Zip

    Delete-Directory $working_dir

    TeamCity-PublishArtifact $artifactFilePath

    TeamCity-ReportBuildStatus 'SUCCESS' "Publishing build artifact $artifactFilePath"
}

Function ILMerge-Assemblies ([string] $sourceDir, [string] $destinationDir, [string] $sourceAssembly, [string] $assembliesToMerge, [string] $targetFramworkVersion) {
    Create-Directory $destinationDir

    $targetplatform = $null
    if (($targetFramworkVersion -eq "v4.5") -or ($targetFramworkVersion -eq "v4.0")) {
        $v4_net_version = (Resolve-Path -Path "$env:windir\Microsoft.NET\Framework\v4.0*")
        $targetplatform = "/targetplatform:`"v4,$v4_net_version`""
    }

    $assemblies = ""
    ForEach ($assembly in $assembliesToMerge.Split(";", [StringSplitOptions]"RemoveEmptyEntries")) {
        if (Test-Path -Path "$sourceDir\$assembly") {
            $assemblies += "$sourceDir\$assembly "
        } else {
            $assemblies += "$assembly "
        }
    }

    exec { & (Resolve-Path -Path "$((Get-PackagePath ilmerge))\ILMerge.exe") "$sourceDir\$sourceAssembly" `
        $assemblies `
        /out:"$destinationDir\$sourceAssembly" `
        /keyfile:"$sign_file" `
        /t:library `
        $targetplatform }
}

Function Create-Directory([string] $directory_name) {
    if (!(Test-Path -Path $directory_name)) {
        New-Item $directory_name -ItemType Directory | Out-Null
    }
}

Function Delete-Directory([string] $directory_name) {
    "Removing Directory: $directory_name)"
    Remove-Item -Force -Recurse $directory_name -ErrorAction SilentlyContinue
}

Function Get-PackagePath ([string] $packageName) {
    $packagePath = Get-ChildItem "$packages_dir\$packageName.*" |
                        Sort-Object Name -Descending | 
                        Select-Object -First 1

    Return "$packagePath"
}