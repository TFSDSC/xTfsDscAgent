# Introduction 
xTfsDscAgent is a Powershell Desire-State Module to install an configure a TFS / VSTS Build Agents.  
You can use this to automate the provisinig of new Agents as you need it.

# Getting Started

To start it is helpful to know about DSC and know how it works. [Here](https://docs.microsoft.com/en-us/powershell/dsc/overview) is a good documentation for this.

To write a config for your agent you must import this Module in your configuratoin.
After this you can use the xTfsDscAgent to configure the agents. In the following table you can see what parameters we currently support:  

| Parameter | Requiered | Description |
| --------- | --------- | ---------- |
| Agentfolder| true | The folder in this the agent will install. This is the key for DSC tho identify is the agent currently there|
| Ensure | true | This is a default DSC Parameter, that describe if the configuration must add or remove the agent. |
| serverUrl | true | This is the url for the VSTS or TFS server. Importent: only input the server url! Dont add the collection name or somethink like this! |
| AgentVersion | false | The Agentversion you want to install and configure. The default is latest. |
| AgentPool | false | The AgentPool the agent joins after installation. The default is default |
| Deploymentpool | false | The Deploymentpool the agent joins after installation. |
| AgentName | false | Here you can define a custom name for the agent. The Default is 'default-' and a Guid |
| AgentAuth | false | This is a option to use all supported auth-options for TFS or VSTS. The Default is 'Integrated'. (This you must change for VSTS!) |
| AgentRunAsService | false | This is a option to run the agent in a windows service. This option only works on windows! The defualt is false.
| WorkFolder |false | Here you can set a custom path. In this Path the Agent will do the work from the build and release jobs from VSTS / TFS. The default option is '_work' in the agentfolder. |
| AgentUser | true | You you must enter the credetials of the service account that have acess to register new agents and run builds. The password is only needed for some auth mechanics! See the TFS Agent doucmentation for this. |
| UserToken | false | Here you can paste a PAT. This is only use for PAT auth! Default is empty | 
| ReplaceAgent | false | This define is the registrion can override exsisting registions with the same agent name. The default is false |

# Example
Important: First install this powershell module in a psmodule path!
Here you can see a example for a config for a agent:  

```PS
Configuration sampleConfigBuildAgent {

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [PsCredential] $agentCredential
    )    
    Import-DscResource -ModuleName xTfsDscAgent -ModuleVersion 1.0.74
    Node $AllNodes.Where{$_.Role -eq 'TfsBuildAgent'}.NodeName
    {
        
        xTfsDscBuildAgent buildAgent {
            AgentFolder = "C:\Agent\"
            Ensure      = "Present"
            serverUrl   = "https://tfs201801.home01.local/"                
            AgentPool   = "default"                
            AgentUser   = $agentCredential            
        }

        LocalConfigurationManager {
            CertificateID = $node.Thumbprint
        }
    }

    
}

Configuration sampleConfigDeployAgent {

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [PsCredential] $agentCredential
    )    
    Import-DscResource -ModuleName xTfsDscAgent -ModuleVersion 1.0.74
    Node $AllNodes.Where{$_.Role -eq 'TfsDeployAgent'}.NodeName
    {
        
        xTfsDscDeployAgent deployAgent {
            AgentFolder = "C:\Agent\"
            Ensure      = "Present"
            serverUrl   = "https://tfs201801.home01.local/"                
            AgentPool   = "deployPool"                
            AgentUser   = $agentCredential            
        }

        LocalConfigurationManager {
            CertificateID = $node.Thumbprint
        }
    }

    
}
```

To run this config you must save this in a file with the name sampleConfig.ps1.
After this you can run the config like any other dsc config:
```PS
$ConfigData = @{
    AllNodes = @(
        @{
            NodeName             = "Agent01.home01.local"
            CertificateFile      = ".\certs\agent01.publickey.cer"
            Thumbprint           = "******"
            Role                 = "TfsAgent"
            PSDscAllowDomainUser = $true
        }
    )
}

mkdir .\mofs -Force
#Loding config
. .\sampleConfig
##compile config
sampleConfigBuildAgent -ConfigurationData $ConfigData -agentCredential (Get-Credential) -OutputPath .\mofs
sampleConfigDeployAgent -ConfigurationData $ConfigData -agentCredential (Get-Credential) -OutputPath .\mofs
#Run Config
Set-DscLocalConfigurationManager .\mofs -Verbose
Start-DscConfiguration .\mofs -Verbose -Wait

```

# Build and Test
TODO: Describe and show how to build your code and run the tests. 

# Contribute
TODO: Explain how other users and developers can contribute to make your code better. 

If you want to learn more about creating good readme files then refer the following [guidelines](https://www.visualstudio.com/en-us/docs/git/create-a-readme). You can also seek inspiration from the below readme files:
- [ASP.NET Core](https://github.com/aspnet/Home)
- [Visual Studio Code](https://github.com/Microsoft/vscode)
- [Chakra Core](https://github.com/Microsoft/ChakraCore)
