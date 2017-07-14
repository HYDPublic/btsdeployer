# Help file for artifacts processing settings
# File Name  : readme_artifacts.txt
# Author     : W.Schneider, wschneider@uapinc.com
{
	# Configuration of BizTalk Artifacts that will be processed before the installation/deploy.
	"PreProcessing" : {
		# Configuration of BizTalk Artifacts that will be enabled before the installation/deploy.
		"Enable" : {	
			# List of receive locations parameters to search. 
			# One or more of the following properties are available to use simultaneously:
			# - Name: Name of the receive location.
			# - ReceivePort: Name of the receive port.
			# - Application: Name of the application.
			# - TransportType: Name of the configured adapter.
			# - ReceiveHandler: Name of the configured host.
			"ReceiveLocations" : [
				{
					"TransportType" : "MSMQ", 
					"Application" : "XX.Interface.GenOnRampSvc.Out"
				},
				{
					"Name" : "GenericOnRampFileReceiveLocation"
				}
			],
			# List of send ports parameters to search. 
			# One or more of the following properties are available to use simultaneously:
			# - Name: Name of the send port.
			# - Application: Name of the application.
			# - TransportType: Name of the configured adapter.
			# - SendHandler: Name of the configured host.
			"SendPorts" : [
				{
					"TransportType" : "FTP",
					"Application" : "SC.Interface.Vendors.Out"
				}
			],
			# List of orchestrations parameters to search. 
			# One or more of the following properties are available to use simultaneously:
			# - Name: Name of the orchestration.
			# - Application: Name of the application.
			# - Host: Name of the configured host.
			"Orchestrations" : [
				{
					"Host" : "SupplyChainReceive"
				},
				{
					"Host" : "SupplyChainSend"
				}
			],
			# List of application parameters to search. 
			# One or more of the following properties are available to use simultaneously:
			# - Name: Name of the application.
			"Applications" : [
				{
					"Name" : "Microsoft.Practices.ESB"
				}
			]
		},
		# Configuration of BizTalk Artifacts that will be disabled before the installation/deploy.
		"Disable" : {
			"SendPorts" : [
				{
					"Application" : "SC.Interface.SalesOrder.In"
				}
			],
			"Applications" : [
				{
					"Name" : "SC.Interface.Distro.Out"
				}
			]
		}
	},
	# Configuration of BizTalk Artifacts that will be processed after the installation/deploy.
	"PostProcessing" : {
		# Configuration of BizTalk Artifacts that will be enabled after the installation/deploy.
		"Enable" : {
			"SendPorts" : [
				{
					"Application" : "SC.Interface.SalesOrder.In"
				}
			],
			"Applications" : [
				{
					"Name" : "SC.Interface.Distro.Out"
				}
			]
		},
		# Configuration of BizTalk Artifacts that will be disabled after the installation/deploy.
		"Disable" : {	
			"ReceiveLocations" : [
				{
					"TransportType" : "MSMQ", 
					"Application" : "XX.Interface.GenOnRampSvc.Out"
				},
				{
					"Name" : "GenericOnRampFileReceiveLocation"
				}
			],
			"SendPorts" : [
				{
					"TransportType" : "FTP",
					"Application" : "SC.Interface.Vendors.Out"
				}
			],
			"Orchestrations" : [
				{
					"Host" : "SupplyChainReceive"
				},
				{
					"Host" : "SupplyChainSend"
				}
			],
			"Applications" : [
				{
					"Name" : "Microsoft.Practices.ESB"
				}
			]
		}
	}
}