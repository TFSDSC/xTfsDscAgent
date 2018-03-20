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
class xTfsDscAgent {
    [DscProperty(Key)]
    [string]$AgentFolder;
    [DscProperty(Mandatory)]
    [Ensure]$Ensure;
    # https://tfs.t-systems.eu/
    [DscProperty(Mandatory)]
    [string] $serverUrl;
    # 2.117.2
    [DscProperty()]
    [string] $AgentVersion = "latest";
    [DscProperty()]
    [string] $AgentPlatform = "win7-x64";
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
                    $downloadUri = $this.getAgentDownLoadUri($this.serverUrl, $this.AgentVersion, $this.AgentPlatform);
                    $this.downloadAgent($downloadUri, $zipPath);
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
            $this.installAgent($this.getRemoveString());
            Remove-Item $this.AgentFolder -Recurse -Force;
        }
    }
    [bool] Test() {
        $this.prepearePowershell();
        $this.ToStringVerbose();
        $testResult = $this.getTestResult();
        $isPresent = $true;
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
        if (!$testResult.AgentUrlOkay) {
            Write-Verbose ("The Agent hasn't the '" + $this.serverUrl + "' as TFS / VSTS Url configured.");
            $isPresent = $false;
        }

        if ($this.Ensure -eq [Ensure]::Present) {
            return $isPresent;
        }
        else {
            return -not $isPresent;
        }
    }
    [xTfsDscAgent]Get() {
        $this.prepearePowershell();
        $this.ToStringVerbose();
        $result = [xTfsDscAgent]::new();         
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
        $propertyNames = $this | Get-Member | ?{$_.MemberType -like "Property"} | %{$_.Name};
        $propertyNames | %{Write-Verbose $_};
        $propertyNames | %{Select-Object -InputObject $this -ExpandProperty $_} | %{Write-Verbose $_ -Verbose};
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
        $result.AgentUrlOkay = $this.serverUrl -eq $getResult.serverUrl;
        Write-Verbose ("The Version: " + $getResult.AgentVersion + " Should be: " + $this.AgentVersion);
        if ($this.AgentVersion -eq "latest") {
            if ($this.serverUrl.Length -gt 0) {
                $versionObject = $this.getLatestVersion($this.getAllAgentThatAreAvabiled($this.serverUrl), $this.AgentPlatform).version;
                $version = $versionObject.major.ToString() + "." + $versionObject.minor.ToString() + "." + $versionObject.patch.ToString();
                $result.AgentVersionOkay = $getResult.AgentVersion -eq $version;
            }
            else {
                $result.AgentVersionOkay = $false;
            }            
        }
        else {
            # this doesn't working. Why?            
            $result.AgentVersionOkay = $this.AgentVersion -eq $getResult.AgentVersion;
        }
        return $result;
    }

    [void] installAgent([string] $configureString) {
        Write-Verbose ("Configure Agent with this parameters: " + $configureString);        
        $fullString = ($this.AgentFolder + "\config.cmd") + " " + $configureString;
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($fullString)
        #$encodedCommand = [Convert]::ToBase64String($bytes)
        # & powershell.exe -encodedCommand $encodedCommand;
        Write-Verbose ("Start installation: " + (Get-Date));
        $process = Start-Process ($this.AgentFolder + "\config.cmd") -ArgumentList $configureString -Verbose -Debug -PassThru;
        $process.WaitForExit();             
        Write-Verbose ("Installation success" + (Get-Date));
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
        $configstring += (" --url " + $this.serverUrl);
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
            $versionObject = $this.getLatestVersion($this.getAllAgentThatAreAvabiled($this.serverUrl)).version;
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
        $agentVersionsUrl = $serverUrl + "_apis/distributedTask/packages/agent";
        $webResult = Invoke-WebRequest $agentVersionsUrl -Credential $this.AgentUser -UseBasicParsing;
        $agentJson = ConvertFrom-Json -InputObject $webResult.Content;
        return $agentJson.value;
    }
}