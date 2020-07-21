$psdDictionary = (pwd).Path + "\src\xTfsDscAgent";
$psdFileName = "xTfsDscAgent.psd1";
$psdData = Import-LocalizedData -BaseDirectory $psdDictionary -FileName $psdFileName;
$versionParts = $psdData.ModuleVersion.Split('.');

$versionParts[2] = ([int]$versionParts[2]) + 1;
$psdData.ModuleVersion = $versionParts -join ".";

Update-ModuleManifest -ModuleVersion $psdData.ModuleVersion -Path ($psdDictionary + "\" + $psdFileName);

$outModuleFolder = ".\out\xTfsDscAgent\" + $psdData.ModuleVersion;
$dscFolderName = "xTfsDscAgent" + "_" + $psdData.ModuleVersion;
$outDSCFolder = ".\out\" + $dscFolderName;
mkdir ($outModuleFolder) -Force -Verbose;
mkdir ($outDSCFolder) -Force -Verbose;

Copy-Item -Path ($psdDictionary + "/" + $psdFileName) -Destination $outModuleFolder;
$dscResourceFolder = $outModuleFolder + "/xTfsDscAgent/DscResources/" + $psdFileName.Split('.')[0];
mkdir ($dscResourceFolder) -Force;
Copy-Item -Path ($psdDictionary + "\*") -Exclude "*.psd1" -Container -Destination $dscResourceFolder;
#Copy-Item -Path ($psdDictionary + "\*") -Destination $outModuleFolder -Container;
Copy-Item -Path ($psdDictionary + "\*") -Destination $outDSCFolder -Container;


Compress-Archive -Path $outDSCFolder -DestinationPath (".\out\" + $dscFolderName + ".zip") -Verbose -CompressionLevel NoCompression;
rm -Recurse -Force $outDSCFolder

New-DscChecksum (".\out\") -Verbose