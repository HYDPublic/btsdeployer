# Help file for settings parameters
# File Name  : readme_settings.txt
# Author     : W.Schneider, wschneider@uapinc.com
{
	# Environment configuration. Refer to available environments configured for BizTalk Deployment Framework.
	# Valid values: "Dev", "Test", "TestHalfCooked", QA" ,"QAHalfCooked" ,"Prod"
	"Environment" : "Dev",
	# List of servers where the packages will be installed/deployed.
	"Servers" : [
		{
			# Full hostname of the server.
			"Hostname" : "smuapbtsdap26.uapinc.com",
			# Switch for turning on/off the undeployment/deployment at BizTalk Server databases.
			"DeployBizTalkMgmtDB" : true,
			# BizTalk Deployment Framework configuration node that should be used,
			"Node" : 1
		}
	]
}