@echo off
Powershell.exe -ExecutionPolicy RemoteSigned -Command "& { ".\scripts\btsdeployer_main.ps1" -Mock -Automatic -VerboseOutput -EnvironmentSettings ".\config\btsdeployer_environment.ini" -ArtifactsSettings ".\config\btsdeployer_artifacts.ini" -OutTranscript ".\log\btsdeployer_console.log" -ApplicationSource ".\msi" -LogRepository ".\log" }
pause