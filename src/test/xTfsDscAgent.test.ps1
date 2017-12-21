using module ..\xtfsDscAgent\xTfsDscAgent.psm1
$xTfsUserAccount = $null;
$serverurl = 'https://tfs201801.home01.local/';
$version = 'latest';
$platform = 'win7-x64';
$agentFolder = '';
$zipPath = '';

Describe 'Test installation of TFSAgent' {    
    $xTfsAgentInstance = $null;

    BeforeAll {
        
        # create a pscredential object for the auth stuff
        $user = [System.Environment]::GetEnvironmentVariable('user', [System.EnvironmentVariableTarget]::User);
        $passwort = ConvertTo-SecureString ([System.Environment]::GetEnvironmentVariable('password', [System.EnvironmentVariableTarget]::User)) -AsPlainText -Force;        
        $xTfsUserAccount = New-Object System.Management.Automation.PSCredential ($user, $passwort);

        $privateInstance = [xtfsDscAgent]::new();
        $privateInstance.AgentUser = $xTfsUserAccount;
        $agentFolder = ".\testspace\cache";
        $privateInstance.AgentFolder = $agentFolder;


        #download a cache for all stuff that must work with the download
        $zipPath = $privateInstance.AgentFolder + "\agent.zip";    
        mkdir $privateInstance.AgentFolder -Force;    
        $downloadUri = $privateInstance.getAgentDownLoadUri($serverurl, $version, $platform);
        if (!(Test-Path $zipPath) -and !(Test-Path ($privateInstance.AgentFolder + '\config.cmd'))) {
            $privateInstance.downloadAgnet($downloadUri, $zipPath);
        }        
        if (!(Test-Path ($privateInstance.AgentFolder + '\config.cmd'))) {
            $privateInstance.unpackAgentZip($zipPath);
        }        
    }

    BeforeEach {
        Write-Verbose "Create instance of xTfsDscAgent that's use for testing";
        $xTfsAgentInstance = [xTfsDscAgent]::new();
        $xTfsAgentInstance.AgentUser = $xTfsUserAccount;
        $xTfsAgentInstance.serverUrl = 'https://tfs201801.home01.local/';
        $xTfsAgentInstance.AgentPool = 'default';
        $xTfsAgentInstance.AgentFolder = '.\testspace\temp';
        $xTfsAgentInstance.Ensure = [Ensure]::Present;
    }

    It 'try to get all avaibeld agents' {        
        $url = $xTfsAgentInstance.serverUrl;
        $result = $xTfsAgentInstance.getAllAgentThatAreAvabiled($url);        
        ($result.Length -eq 5) | Should Be  $true;
        foreach ($os in $result) {
            $os.type | Should be 'agent';
        }
    }

    It 'try to get a download url for platform windows and version latest' {
        $url = $xTfsAgentInstance.serverUrl;
        $plattform = $xTfsAgentInstance.AgentPlatform;
        $version = $xTfsAgentInstance.AgentVersion;
        $result = $xTfsAgentInstance.getAgentDownLoadUri($url, $version, $plattform);
        $result.Contains('https') | Should Be $true;
        $result.Contains('go.microsoft.com') | Should Be $true;
        $result.Contains('fwlink') | Should be $true;
        $result.Contains('linkid') | Should be $true;
    }

    It 'try to get a download url for platform ubuntu and version 2.122.1' {
        $xTfsAgentInstance.AgentPlatform = 'ubuntu.16.04-x64';
        $xTfsAgentInstance.AgentVersion = '2.122.1';
        $url = $xTfsAgentInstance.serverUrl;
        $plattform = $xTfsAgentInstance.AgentPlatform;
        $version = $xTfsAgentInstance.AgentVersion;
        $result = $xTfsAgentInstance.getAgentDownLoadUri($url, $version, $plattform);
        $result.Contains('https') | Should Be $true;
        $result.Contains('go.microsoft.com') | Should Be $true;
        $result.Contains('fwlink') | Should be $true;
        $result.Contains('linkid') | Should be $true;
    }

    it ('try to download and unpack the agent for platfom windows and version latest') {
        $url = $xTfsAgentInstance.serverUrl;
        $plattform = $xTfsAgentInstance.AgentPlatform;
        $version = $xTfsAgentInstance.AgentVersion;
        $zipPath = $xTfsAgentInstance.AgentFolder + "\agent.zip";
        mkdir $xTfsAgentInstance.AgentFolder -Force;
        $downloadUri = $xTfsAgentInstance.getAgentDownLoadUri($url, $version, $plattform);
        $xTfsAgentInstance.downloadAgnet($downloadUri, $zipPath);
        Test-Path $zipPath | Should Be $true;
        (Get-ChildItem $zipPath).Length -gt 80mb | Should Be $true;

        #unpack
        $xTfsAgentInstance.unpackAgentZip($zipPath);
        (Get-ChildItem $xTfsAgentInstance.AgentFolder).Length -eq 4 | Should Be $true;
    }

    it 'get the configuration string for the config cmd' {
        $configstring = $xTfsAgentInstance.getConfigurationString();
        $configstring -ne $null | Should Be $true;
        Write-Verbose $configstring;
        $configstring.Contains($xTfsAgentInstance.serverUrl) | Should Be $true;
        $configstring.Contains($xTfsAgentInstance.AgentUser.UserName) | Should Be $true;
        $configstring.Contains($xTfsAgentInstance.AgentPool) | Should be $true;
        $configstring.Contains('unattended') | Should be $true;
    }

    It 'not as service' {
        $cacheOrigAgentfolder = $xTfsAgentInstance.AgentFolder;
        $xTfsAgentInstance.AgentFolder = $agentFolder        
        $xTfsAgentInstance.AgentRunAsService = $false;
        
        $xTfsAgentInstance.installAgent($xTfsAgentInstance.getConfigurationString());

        #If the agent is configure as Service the agent starting after config automatic
        if (!$xTfsAgentInstance.AgentRunAsService) {
            $xTfsAgentInstance.startAgent();    
        }

        $xTfsAgentInstance.AgentFolder = $cacheOrigAgentfolder;

    }

    It 'as service ' {
        $cacheOrigAgentfolder = $xTfsAgentInstance.AgentFolder;
        $xTfsAgentInstance.AgentFolder = $agentFolder                        
        
        $xTfsAgentInstance.installAgent($xTfsAgentInstance.getConfigurationString());

        #If the agent is configure as Service the agent starting after config automatic
        if (!$xTfsAgentInstance.AgentRunAsService) {
            $xTfsAgentInstance.startAgent();    
        }

        $xTfsAgentInstance.AgentFolder = $cacheOrigAgentfolder;
    }

    It 'remove agent' {
        #install
        $xTfsAgentInstance.Set();
        #remove
        $xTfsAgentInstance.Ensure = [Ensure]::Absent;
        $xTfsAgentInstance.Set();
    }

    AfterEach {
        Write-Verbose 'remove agent';
        Sleep 1;
        if ((Test-Path ($xTfsAgentInstance.AgentFolder + '\config.cmd'))) {
            Start-Process -FilePath PowerShell -LoadUserProfile  -Verbose -Credential $xTfsAgentInstance.AgentUser -Wait -ArgumentList '-Command', ($xTfsAgentInstance.AgentFolder + '\config.cmd' + ' remove --unattended --auth integrated'); 
        }
        if ((Test-Path ($agentFolder + '\config.cmd'))) {
            Start-Process -FilePath PowerShell -LoadUserProfile  -Verbose -Credential $xTfsAgentInstance.AgentUser -Wait -ArgumentList '-Command', ($agentFolder + '\config.cmd' + ' remove --unattended --auth integrated'); 
        }

        Write-Verbose 'Cleanup Agent folder';
        if (Test-Path $xTfsAgentInstance.AgentFolder) {
            Remove-Item -Recurse -Force $xTfsAgentInstance.AgentFolder;
        }        
    }

}