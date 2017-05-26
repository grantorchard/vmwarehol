<#
    .SYNOPSIS
    Create an NSX topology for the hands on labs.
    
    .DESCRIPTION
    Deploys an Logical Switch, Edge Gateway, Logical Router and stiches it together using OSPF. Also peers to the vPod Router.
    Ensure you have both PowerCLI and PowerNSX installed before running this.
    PowerCLI: Install-Module -Name VMware.PowerCLI
    PowerNSX: $Branch="master";$url="https://raw.githubusercontent.com/vmware/powernsx/$Branch/PowerNSXInstaller.ps1"; try { $wc = new-object Net.WebClient;$scr = try { $wc.DownloadString($url)} catch { if ( $_.exception.innerexception -match "(407)") { $wc.proxy.credentials = Get-Credential -Message "Proxy Authentication Required"; $wc.DownloadString($url) } else { throw $_ }}; $scr | iex } catch { throw $_ }

#>

# --- Variables

$ClusterName = "RegionA01-MGMT01"
$NSXTransportZone = "RegionA0-Global-TZ"
$NSXTransitNetwork = "Transit Network"
$DatastoreName = "RegionA01-ISCSI01-COMP01"
$EdgeUplinkPG = "VM-RegionA01-vDS-MGMT"
$UplinkName = "Uplink"
$EdgeUplinkAddress = "192.168.100.4"
$EdgeInternalLinkName = "Internal"
$EdgeInternalAddress = "192.168.200.1"
$EdgeName = "ESG"
$EdgeRouterId = "192.168.100.4"
$LDRUplinkAddress = "192.168.200.2"
$LDRName = "LDR"
$LDRRouterId = "192.168.200.2"
$LDRProtocolAddress = "192.168.200.3"
$LDRForwardingAddress = "192.168.200.2"



# --- Enable DRS for Edge Deployment
$DRSEnable = Get-Cluster $ClusterName | Set-Cluster -Drsenabled $true -confirm:$false

# --- Create Logical Switch for Transit Network
$TransitLS = Get-NSXTransportZone $NSXTransportZone | New-NSXLogicalSwitch -Name $NSXTransitNetwork

# --- Create Edge Services Gateway

$TransitLS = Get-NSXLogicalSwitch $NSXTransitNetwork
$Datastore = Get-Datastore $DatastoreName
$Cluster = Get-Cluster $ClusterName
$UplinkPG = Get-VDPortgroup $EdgeUplinkPG

$UplinkIf0 = New-NsxEdgeInterfaceSpec -Name $UplinkName -Type Uplink -ConnectedTo $UplinkPG -PrimaryAddress $EdgeUplinkAddress -SubnetPrefixLength 24 -Index 0
$InternalIf0 = New-NsxEdgeInterfaceSpec -Name $EdgeInternalLinkName -Type Internal -ConnectedTo $TransitLS -PrimaryAddress $EdgeInternalAddress -SubnetPrefixLength 29 -Index 1
New-NsxEdge -Name $EdgeName -Datastore $Datastore -cluster $Cluster -Password VMware1!VMware1! -FormFactor compact -FwEnabled -FwDefaultPolicyAllow -AutoGenerateRules -Interface $UplinkIf0,$InternalIf0

# --- Configure OSPF on ESG
Get-NsxEdge $EdgeName | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -EnableOspfRouteRedistribution -RouterId $EdgeRouterId -confirm:$false
Get-NsxEdge $EdgeName | Get-NsxEdgerouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false
Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId 10 -Type normal -confirm:$false
$EdgeUplinkInt = Get-NSXEdge $EdgeName | Get-NSXEdgeInterface | Where-Object { $_.name -eq $UplinkName}
Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId 10 -IgnoreMTU:$true -vNic $EdgeUplinkInt.index -confirm:$false
$EdgeInternallinkInt = Get-NSXEdge $EdgeName | Get-NSXEdgeInterface | Where-Object { $_.name -eq $EdgeInternalLinkName}
Get-NsxEdge ESG | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId 10  -vNic $EdgeInternallinkInt.index -confirm:$false

# --- Deploy Logical Router
$UplinkIf0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $UplinkName -ConnectedTo $TransitLS -PrimaryAddress $LDRUplinkAddress -SubnetPrefixLength 29
New-NsxLogicalRouter -name $LDRName -interface $UplinkIf0 -managementportgroup $UplinkPG -cluster $Cluster -datastore $Datastore
$LdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | Where-Object { $_.name -eq $UplinkName}
Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic $LdrTransitInt.index -DefaultGatewayAddress $EdgeInternalAddress -confirm:$false

# --- Configure OSPF on LDR

Get-NsxLogicalRouter LDR | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableOspf -EnableOspfRouteRedistribution -RouterId $LDRRouterId -ProtocolAddress $LDRProtocolAddress -ForwardingAddress $LDRForwardingAddress  -confirm:$false
Get-NsxLogicalRouter LDR | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 51 | Remove-NsxLogicalRouterOspfArea -confirm:$false
Get-NsxLogicalRouter LDR | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId 10 -Type normal -confirm:$false
$LDRInternallinkInt = Get-NSXLogicalRouter $LDRName | Get-NSXLogicalRouterInterface | Where-Object { $_.name -eq $UplinkName}
Get-NsxLogicalRouter LDR | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId 10 -vNic $LDRInternallinkInt.index -confirm:$false



# --- Disable DRS
$DRSEnable = Get-Cluster RegionA01-MGMT01 | Set-Cluster -Drsenabled $false -confirm:$false