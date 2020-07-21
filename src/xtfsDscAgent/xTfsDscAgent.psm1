enum Ensure{
    Absent
    Present
}
enum AuthMode{
    Integrated
    PAT
    Negotiate
    ALT
}
[DscResource()]
class TfsAgent {
    [DscProperty(Key)]
    [string]$AgentFolder;
    [DscProperty(Mandatory)]
    [Ensure]$Ensure;
    [DscProperty(Mandatory)]
    [string] $serverUrl;
    [DscProperty(Mandatory)]
    [string] $CollectionName;
    [DscProperty()]
    [string] $filePath;
    # 2.117.2
    [DscProperty()]
    [string] $AgentVersion = "latest";
    [DscProperty()]
    [string] $AgentPlatform = "win-x64";
    [DscProperty()]
    [string] $AgentPool;
    [DscProperty()]
    [string] $AgentName = "default";
    [DscProperty()]
    [int] $AgentAuth = [AuthMode]::Integrated;
    [DscProperty()]
    [bool] $AgentRunAsService = $false;
    [DscProperty()]
    [string] $WorkFolder = "_work";
    [DscProperty()]
    [PsCredential] $AgentUser;
    [DscProperty()]
    [string] $UserToken;
    [DscProperty()]
    [bool] $ReplaceAgent = $false;

    [void] prepearePowershell() {
        # I don't know why but sometimes the powershell can't create a secure channel.
        # thanks to the help from here: https://stackoverflow.com/questions/41618766/powershell-invoke-webrequest-fails-with-ssl-tls-secure-channel
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor `
            [Net.SecurityProtocolType]::Tls11 -bor `
            [Net.SecurityProtocolType]::Tls
    }
    [void] Set() {
        $this.prepearePowershell();
        $this.ToStringVerbose();
        if ($this.Ensure -eq [Ensure]::Present) {
            $testResult = $this.getTestResult();
            if (!$testResult.AgentFolderOkay -or (Get-ChildItem -Path $this.AgentFolder).Length -eq 0) {
                Write-Verbose "The AgentFolder doesn't exsists or is empty.";
                mkdir $this.AgentFolder -Force;
                if (!(Test-Path $this.AgentFolder) -or (Get-ChildItem $this.AgentFolder).Length -eq 0) {
                    #install
                    $zipPath = $this.AgentFolder + "\agent.zip";
                    $downloadUri = $this.getAgentDownLoadUri("$($this.serverUrl)/$($this.CollectionName)/", $this.AgentVersion, $this.AgentPlatform);
                    if (!$this.filePath) {
                        $this.downloadAgent($downloadUri, $zipPath);
                    }
                    else {
                        Write-Verbose ("The file path is " + $this.filePath);
                        Copy-Item -Path $this.filePath -Destination $zipPath;
                    }
                    $this.unpackAgentZip($zipPath);
                    $this.installAgent($this.getConfigurationString());
                }
            }
            elseif (!$testResult.AgentVersionOkay) {
                Write-Verbose ("The Agent Version isn't " + $this.AgentVersion);
                #first uninstall current Agentversion
                $this.installAgent($this.getRemoveString());
                Remove-Item $this.AgentFolder -Recurse -Force;
                #then install again
                $this.Set();
            }
            elseif (!$testResult.AgentNameOkay -or !$testResult.AgentWorkFolderOkay -or !$testResult.AgentUrlOkay) {
                Write-Verbose ("The Agent isn't configured rigth.");
                #here we must remove the agent
                $this.installAgent($this.getRemoveString());
                $this.installAgent($this.getConfigurationString());
            }
            #If the agent is configure as Service the agent starting after config automatic
            if (!$this.AgentRunAsService) {
                Write-Verbose "Try to start agent, because it isn't a Windows service."
                $this.startAgent();
            }
            else {
                Write-Verbose "Don't start the agent, because the windows service start automatic.";
            }
        }
        else {
            #uninstall
            $removestring = $this.getRemoveString();
            Write-Verbose $removestring;
            $this.installAgent($this.getRemoveString());
            Remove-Item $this.AgentFolder -Recurse -Force;
        }
    }
    [bool] Test() {
        $this.prepearePowershell();
        $this.ToStringVerbose();
        $testResult = $this.getTestResult();
        $isPresent = $true;
        $currentConfig = $this.Get();
        if (!$testResult.AgentFolderOkay) {
            Write-Verbose "The AgentFolder doesn't exsists";
            $isPresent = $false;
        }
        if (!$testResult.AgentVersionOkay) {
            Write-Verbose ("The Agent Version isn't " + $this.AgentVersion);
            $isPresent = $false;
        }
        if (!$testResult.AgentNameOkay) {
            Write-Verbose ("The Agent Name isn't " + $this.AgentName);
            $isPresent = $false;
        }
        if (!$testResult.AgentWorkFolderOkay) {
            Write-Verbose ("The Agent Workfolder isn't " + $this.WorkFolder);
            $isPresent = $false;
        }
        if([string]::IsNullOrWhiteSpace($currentConfig.serverUrl) -eq $true){
            Write-Verbose "The agent is extracted but not registered."
            $isPresent = $false;
        }
        if (!$testResult.AgentUrlOkay) {
            Write-Verbose ("The Agent hasn't the '" + $this.serverUrl + "' as TFS / VSTS Url configured. It has $($currentConfig.serverUrl)");
            $isPresent = $false;
        }

        if ($this.Ensure -eq [Ensure]::Present) {
            return $isPresent;
        }
        else {
            return -not $isPresent;
        }
    }
    [TfsAgent]Get() {
        $this.prepearePowershell();
        $this.ToStringVerbose();
        $result = [TfsAgent]::new();
        $result.AgentFolder = $this.AgentFolder
        $result.ReplaceAgent = $false
        $agentJsonpath = $this.AgentFolder + "\.agent";
        if (Test-Path $agentJsonpath) {
            $agentJsonFile = ConvertFrom-Json -InputObject (Get-Content $agentJsonpath -Raw);
            $result.WorkFolder = $agentJsonFile.workFolder;
            $result.AgentName = $agentJsonFile.agentName;
            $result.serverUrl = $agentJsonFile.serverUrl;
            $result.AgentPool = $agentJsonFile.poolId;
        }
        #Get agentVersion
        if (Test-Path ($this.AgentFolder + "\config.cmd")) {
            $result.AgentVersion = & ($this.AgentFolder + "\config.cmd") ("--version");
        }
        return $result;
    }
    [void]ToStringVerbose(){
        $propertyNames = $this | Get-Member | Where-Object{$_.MemberType -like "Property"} | ForEach-Object{$_.Name};
        $propertyNames | ForEach-Object{Write-Verbose $_};
        $propertyNames | ForEach-Object{Select-Object -InputObject $this -ExpandProperty $_} | ForEach-Object{Write-Verbose $_ -Verbose};
    }
    [PSCustomObject] getTestResult() {
        $result = [PSCustomObject]@{
            AgentFolderOkay = $false
            AgentVersionOkay = $false
            AgentNameOkay = $false
            AgentWorkFolderOkay = $false
            AgentUrlOkay = $false
        }
        $getResult = $this.Get();
        if ((Test-Path $this.AgentFolder)) {
            $result.AgentFolderOkay = $true;
        }
        if ($this.AgentName -eq "default") {
            $result.AgentNameOkay = $getResult.AgentName.Contains("default");
        }
        else {
            $result.AgentNameOkay = $getResult.AgentName -eq $this.AgentName;
        }
        $result.AgentWorkFolderOkay = $this.WorkFolder -eq $getResult.WorkFolder;
        if($this.serverUrl[$this.serverUrl.Length -1] -ne "/"){
            Write-Verbose "We change the serverURL and add an '/'.";
            $this.serverUrl = "$($this.serverUrl)/";
        }
        $result.AgentUrlOkay = $this.serverUrl -eq $getResult.serverUrl;

        if ($this.AgentVersion -eq "latest") {
            if ("$($this.serverUrl)/$($this.CollectionName)/".Length -gt 2) {
                $versionObject = $this.getLatestVersion($this.getAllAgentThatAreAvabiled("$($this.serverUrl)/$($this.CollectionName)/"), $this.AgentPlatform).version;
                $version = $versionObject.major.ToString() + "." + $versionObject.minor.ToString() + "." + $versionObject.patch.ToString();
                $result.AgentVersionOkay = $getResult.AgentVersion.Trim() -like $version.Trim();
                if($result -eq $false){
                    Write-Verbose "The agent version isn't $version. It is $($getResult.AgentVersion)";
                }
            }
            else {
                $result.AgentVersionOkay = $false;
            }
        }
        else {
            Write-Verbose ("The Version: " + $getResult.AgentVersion + " Should be: " + $this.AgentVersion);
            # this doesn't working. Why?
            $result.AgentVersionOkay = $this.AgentVersion -eq $getResult.AgentVersion;
        }
        return $result;
    }

    [void] installAgent([string] $configureString) {
        $configureStringPasswordObfuscated = $configureString -replace '(?<=--windowslogonpassword \s*).*?(?= --)', '*****'
        Write-Verbose ("Configure Agent with this parameters:" + $configureStringPasswordObfuscated);
        Write-Verbose ("Start installation: " + (Get-Date));
        cmd /c "$($this.AgentFolder)\config.cmd $configureString";
        Write-Verbose ("Installation completed: $(Get-Date)");
    }
    [void] startAgent() {
        $startProgrammPath = $this.AgentFolder + "run.cmd";
        Invoke-Command -ScriptBlock {Start-Process $args[0]} -ArgumentList $startProgrammPath -InDisconnectedSession -ComputerName localhost
        Write-Verbose "Start sucess";
    }
    [string] getRemoveString() {
        $removestring = " remove";
        $removestring += $this.authString();
        $removestring += " --unattended";
        return $removestring;
    }
    [string] getConfigurationString() {
        $configstring = "";
        $configstring += (" --url " + "$($this.serverUrl)/$($this.CollectionName)/");
        $configstring += (" --pool " + $this.AgentPool);
        $configstring += (" --work " + $this.WorkFolder);
        $configstring += $this.authString();
        if ($this.AgentRunAsService) {
            if ($this.AgentAuth -ne [int][AuthMode]::Integrated) {
                throw "To run the agent as service your auth must be set to integrated"
            }
            if ([string]::IsNullOrEmpty($this.AgentUser.UserName) -or [string]::IsNullOrEmpty($this.AgentUser.GetNetworkCredential().Password)) {
                throw "To run the agent as service you need a username and a password"
            }
            $configstring += " --runasservice";
            $configstring += (" --windowslogonaccount " + $this.AgentUser.UserName);
            $configstring += (" --windowslogonpassword " + ($this.AgentUser.GetNetworkCredential().Password));
        }
        if ($this.AgentName -eq "Default") {
            $configstring += (" --agent " + $this.AgentName + "-" + ((New-Guid).ToString()))
        }
        else {
            $configstring += (" --agent " + $this.AgentName);
        }
        if ($this.ReplaceAgent) {
            $configstring += " --replace"
        }
        $configstring += " --unattended";
        #accepteula isn't avaibeld in tfs agents for tfs 2018. The new parameter is --acceptTeeEula and must only use for linux and mac agents.
        #$configstring += " --accepteula";
        return $configstring;
    }
    [string] authString() {
        $configstring = "";
        switch ($this.AgentAuth) {
            ([int][AuthMode]::Integrated) {
                $configstring += " --auth Integrated"
            }
            ([int][AuthMode]::PAT) {
                if ($this.UserToken -eq $null -or $this.UserToken.Length -eq 0) {
                    throw "For PAT Auth you need a UserToken!"
                }
                $configstring += " --auth PAT --token " + $this.UserToken;
            }
            ([int][AuthMode]::Negotiate) {
                if (![string]::IsNullOrEmpty($this.AgentUser.UserName) -and ![string]::IsNullOrEmpty($this.AgentUser.GetNetworkCredential().Password)) {
                    throw "For Negotiate Auth you need a username and a password!";
                }
                $configstring += " --auth Negotitate --username " + $this.AgentUser.UserName + " --password " + $this.AgentUser.GetNetworkCredential().Password;
            }
            ([int][AuthMode]::ALT) {
                if (![string]::IsNullOrEmpty($this.AgentUser.UserName) -and ![string]::IsNullOrEmpty($this.AgentUser.GetNetworkCredential().Password)) {
                    throw "For ALT Auth you need a username and a password!";
                }
                $configstring += " --auth ALT --username " + $this.AgentUser.UserName + " --password " + $this.AgentUser.GetNetworkCredential().Password;
            }
            Default {
                throw "Not know authmode set! Please set a valid authmode!"
            }
        }
        return $configstring;
    }
    [bool] checkIfCurrentAgentVersionIsInstalled() {
        $version = $this.AgentVersion;
        if ($this.AgentVersion -eq "latest") {
            $versionObject = $this.getLatestVersion($this.getAllAgentThatAreAvabiled("$($this.serverUrl)/$($this.CollectionName)/")).version;
            $version = $versionObject.major + "." + $versionObject.minor + "." + $versionObject.patch;
        }
        return $false;
        # we must find a way to do this!
    }

    [void] unpackAgentZip([string] $zipPath) {
        Expand-Archive -Path $zipPath -DestinationPath $this.AgentFolder
        Remove-Item $zipPath
    }
    [void] downloadAgent([string] $url, [string] $zipPath) {
        Invoke-WebRequest $url -OutFile $zipPath -UseBasicParsing -Verbose;
    }
    [string] getAgentDownLoadUri([string] $serverUrl, [string] $version, [string] $platfrom) {
        $allagents = $this.getAllAgentThatAreAvabiled($serverUrl);
        if ($version -eq "latest") {
            return $this.getLatestVersion($allagents, $platfrom).downloadUrl;
        }
        else {
            return $this.getspecifivVersion($allagents, $version, $platfrom).downloadUrl;
        }
    }
    [PsCustomObject] getLatestVersion([PSCustomObject] $agents, [string] $platfrom) {
        return ($agents |
                Where-Object {$_.type -eq "agent" -and $_.platform -eq $platfrom} |
                Sort-Object createdOn -Descending)[0];
    }
    [PsCustomObject] getspecifivVersion([PsCustomObject] $agents, [string] $version, [string] $platform) {
        $splitedVersion = $version.Split(".")
        [Array]$result = $agents |
            Where-Object {$_.type -eq "agent" -and $_.platform -eq $platfrom -and $_.version.major -eq $splitedVersion[0] -and $_.version.minor -eq $splitedVersion[1] -and $_.version.patch -eq $splitedVersion[2] };
        if ($result.Length -eq 0) {
            throw "version are not found! Maybe it is not compatible with your TFS version!";
        }
        return ($result | Sort-Object createdOn -Descending)[0];
    }
    [PSCustomObject] getAllAgentThatAreAvabiled([string] $serverUrl) {
        $agentVersionsUrl = "$($this.serverUrl)/$($this.CollectionName)/" + "_apis/distributedTask/packages/agent";
        $webResult = Invoke-WebRequest $agentVersionsUrl -Credential $this.AgentUser -UseBasicParsing;
        $agentJson = ConvertFrom-Json -InputObject $webResult.Content;
        return $agentJson.value;
    }
}
