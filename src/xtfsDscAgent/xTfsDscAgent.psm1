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
    [string]$AgentFolder
    [DscProperty(Mandatory)]
    [Ensure]$Ensure
    # https://tfs.t-systems.eu/
    [DscProperty(Mandatory)]
    [string] $serverUrl
    # 2.117.2
    [DscProperty()]
    [string] $AgentVersion = "latest"
    [string] $AgentPlatform = "win7-x64"
    [DscProperty()]
    [string] $AgentPool
    [DscProperty()]
    [string] $AgentName = "default"
    [DscProperty()]
    [AuthMode] $AgentAuth = [AuthMode]::Integrated;
    [DscProperty()]
    [bool] $AgentRunAsService = $false
    [DscProperty()]
    [string] $WorkFolder = "_work"    
    [DscProperty()]
    [PsCredential] $AgentUser
    [DscProperty()]
    [string] $UserToken
    [DscProperty()]
    [bool] $ReplaceAgent = $false;
    
    [void] Set() {
        if ($this.Ensure -eq [Ensure]::Present) {
            if (!(Test-Path $this.AgentFolder)) {
                mkdir $this.AgentFolder -Force;
            }
            if (!(Test-Path $this.AgentFolder) -or (Get-ChildItem $this.AgentFolder).Length -eq 0) {
                #install
                $zipPath = $this.AgentFolder + "\agent.zip";
                $downloadUri = $this.getAgentDownLoadUri($this.serverUrl, $this.AgentVersion, $this.AgentPlatform);
                $this.downloadAgnet($downloadUri, $zipPath);
                $this.unpackAgentZip($zipPath);
                $this.installAgent($this.getConfigurationString());

                #If the agent is configure as Service the agent starting after config automatic
                if (!$this.AgentRunAsService) {
                    $this.startAgent();    
                }
                

            }
            else {
                if (!$this.checkIfCurrentAgentVersionIsInstalled()) {
                    #install newer version
                    #TODO: we don't know how
                }
                else {
                    # reconfiure   
                    $this.installAgent($this.getConfigurationString()); 
                }
                
            }        
        }
        else {
            #uninstall
            $this.installAgent($this.getRemoveString());
            Remove-Item $this.AgentFolder -Recurse -Force;
        }
    }

    [bool] Test() {
        $present = ((Test-Path $this.AgentFolder) -and (Get-ChildItem $this.AgentFolder).Length -gt 0);
        #TODO we must check the version number!
        if ($this.Ensure -eq [Ensure]::Present) {
            return $present;
        }
        else {
            return -not $present;
        }
        return $false;
    }

    [xTfsDscAgent]Get() {
        $result = @{
            AgentFolder       = $this.AgentFolder
            Ensure            = $null
            serverUrl         = ""
            AgentVersion      = ""
            AgentPlatform     = ""
            AgentPool         = ""
            AgentName         = ""
            AgentAuth         = $null
            AgentRunAsService = $null
            ReplaceAgent      = $false
            WorkFolder        = ""
            UserToken         = ""
            AgentUser         = ""
        };
        if ($this.Ensure -eq [Ensure]::Present) {
            if ($this.Test()) {
                $result.Ensure = [Ensure]::Present;    
            }
            else {
                $result.Ensure = [Ensure]::Absent;
            }
            
        }
        else {
            if ($this.Test()) {
                $result.Ensure = [Ensure]::Absent;    
            }
            else {
                $result.Ensure = [Ensure]::Present;
            }
        }
        $agentJsonpath = $this.AgentFolder + "\.agent";
        if(Test-Path $agentJsonpath){
            $agentJsonFile = ConvertFrom-Json -InputObject (Get-Content $agentJsonpath -Raw);
            $result.WorkFolder = $agentJsonFile.workFolder;
            $result.AgentName = $agentJsonFile.agentName;
            $result.serverUrl = $agentJsonFile.serverUrl;
        }
        return $result;
    }

    [void] installAgent([string] $configureString) {
        Write-Verbose ("Configure Agent with this parameters: " + $configureString);
        $configProgrammPath = ($this.AgentFolder + "\config.cmd" + $configureString);
        $powershellcommand = '"Invoke-Expression -Command ' + "'" + $configProgrammPath + "'" + ' -Verbose;"'
        # Start-Job -ScriptBlock {Invoke-Expression $configProgrammPath -Verbose; } -Credential $this.AgentUser | Wait-Job | Receive-Job;
        $output = Start-Process -FilePath PowerShell -LoadUserProfile  -Verbose -Credential $this.AgentUser -Wait -ArgumentList '-Command', $configProgrammPath; 
        Write-Verbose ("" + $output);
        Write-Verbose "Installation success";
    }

    [void] startAgent() {        
        $startProgrammPath = $this.AgentFolder + "\run.cmd";
        Start-Process -FilePath $startProgrammPath;
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
        $configstring += " --url " + $this.serverUrl;
        $configstring += " --pool " + $this.AgentPool;
        $configstring += " --work " + $this.WorkFolder;

        $configstring += $this.authString();

        if ($this.AgentRunAsService) {
            if ($this.AgentAuth -ne [AuthMode]::Integrated) {
                throw "To run the agent as service your auth must be set to integrated"
            }
            if ([string]::IsNullOrEmpty($this.AgentUser.UserName) -or [string]::IsNullOrEmpty($this.AgentUser.GetNetworkCredential().Password)) {
                throw "To run the agent as service you need a username and a password"
            }
            $configstring += " --runasservice";
            $configstring += " --windowslogonaccount " + $this.AgentUser.UserName;
            $configstring += " --windowslogonpassword " + $this.AgentUser.GetNetworkCredential().Password;
        }

        if ($this.AgentName -eq "Default") {
            $configstring += " --agent " + $this.AgentName + "-" + (New-Guid).ToString()
        }
        else {
            $configstring += " --agent " + $this.AgentName;
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
        switch ($this.AgentAuth.ToString()) {
            ([AuthMode]::Integrated).ToString() {
                $configstring += " --auth Integrated"
            }
            ([AuthMode]::PAT).ToString() {
                if ($this.UserToken -eq $null -or $this.UserToken.Length -eq 0) {
                    throw "For PAT Auth you need a UserToken!"
                }
                $configstring += " --auth PAT --token " + $this.UserToken;
            }
            ([AuthMode]::Negotiate).ToString() {
                if (![string]::IsNullOrEmpty($this.AgentUser.UserName) -and ![string]::IsNullOrEmpty($this.AgentUser.GetNetworkCredential().Password)) {
                    throw "For Negotiate Auth you need a username and a password!";
                }
                $configstring += " --auth Negotitate --username " + $this.AgentUser.UserName + " --password " + $this.AgentUser.GetNetworkCredential().Password;
            }
            ([AuthMode]::ALT).ToString() {
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

    [void] downloadAgnet([string] $url, [string] $zipPath) {
        Invoke-WebRequest $url -OutFile $zipPath -UseBasicParsing;
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
        $result = $agents | 
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