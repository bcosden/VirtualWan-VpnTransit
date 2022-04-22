#!/bin/bash

# VARIABLES
loc1="eastus"
loc2="westus"
rg="vwanvpn"

# create rg
az group create -n $rg -l $loc1

# create virtual wan
az network vwan create -g $rg -n vwanvpn --branch-to-branch-traffic true --location $loc1 --type Standard

az network vhub create -g $rg --name hubeast --address-prefix 10.0.0.0/24 --vwan vwanvpn --location $loc1 --sku Standard
az network vhub create -g $rg --name hubwest --address-prefix 10.0.1.0/24 --vwan vwanvpn --location $loc2 --sku Standard

# create VPN gateways in each Virtual WAN Hub
az network vpn-gateway create -n hubeastvpn23094989 -g $rg --location $loc1 --vhub hubeast  --no-wait
az network vpn-gateway create -n hubwesttvpn2349829 -g $rg --location $loc2 --vhub hubwest --no-wait

# create east branch virtual network
az network vnet create --address-prefixes 10.100.0.0/16 -n branchEast -g $rg -l $loc1 --subnet-name main --subnet-prefixes 10.100.0.0/24
az network vnet subnet create -g $rg --vnet-name branchEast -n GatewaySubnet --address-prefixes 10.100.100.0/26

# create west branch virtual network
az network vnet create --address-prefixes 10.101.0.0/16 -n branchWest -g $rg -l $loc2 --subnet-name main --subnet-prefixes 10.101.0.0/24
az network vnet subnet create -g $rg --vnet-name branchWest -n GatewaySubnet --address-prefixes 10.101.100.0/26

# create pips for VPN GW's in each branch
az network public-ip create -n branchEastGW-pip -g $rg --location $loc1 --sku Standard
az network public-ip create -n branchWestGW-pip -g $rg --location $loc2 --sku Standard

# create VPN gateways
az network vnet-gateway create -n branchEastGW --public-ip-addresses branchEastGW-pip -g $rg --vnet branchEast --asn 65510 --gateway-type Vpn -l $loc1 --sku VpnGw2 --vpn-gateway-generation Generation2 --no-wait
az network vnet-gateway create -n branchWestGW --public-ip-addresses branchWestGW-pip -g $rg --vnet branchWest --asn 65509 --gateway-type Vpn -l $loc2 --sku VpnGw2 --vpn-gateway-generation Generation2 --no-wait

# create spoke1 virtual network
az network vnet create --address-prefixes 10.10.0.0/16 -n spoke1 -g $rg -l $loc1 --subnet-name main --subnet-prefixes 10.10.0.0/24
az network vnet create --address-prefixes 10.11.0.0/16 -n spoke2 -g $rg -l $loc2 --subnet-name main --subnet-prefixes 10.11.0.0/24

# create spoke to Vwan connections
az network vhub connection create -n spoke1conn --remote-vnet spoke1 -g $rg --vhub-name hubeast
az network vhub connection create -n spoke2conn --remote-vnet spoke2 -g $rg --vhub-name hubwest

prState=''
rtState=''
while [[ $prState != 'Succeeded' ]];
do
    prState=$(az network vhub show -g $rg -n hubeast --query 'provisioningState' -o tsv)
    echo "hubeast provisioningState="$prState
    sleep 5
done

while [[ $rtState != 'Provisioned' ]];
do
    rtState=$(az network vhub show -g $rg -n hubeast --query 'routingState' -o tsv)
    echo "hubeast routingState="$rtState
    sleep 5
done

prState=''
while [[ $prState != 'Succeeded' ]];
do
    prState=$(az network vnet-gateway show -g $rg -n branchEastGW --query provisioningState -o tsv)
    echo "branchEastGW provisioningState="$prState
    sleep 5
done

# get bgp peering and public ip addresses of VPN GW and VWAN to set up connection
bgp1=$(az network vnet-gateway show -n branchEastGW -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]' -o tsv)
pip1=$(az network vnet-gateway show -n branchEastGW -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].tunnelIpAddresses[0]' -o tsv)
vwanbgp1=$(az network vpn-gateway show -n hubeastvpn23094989 -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]' -o tsv)
vwanpip1=$(az network vpn-gateway show -n hubeastvpn23094989 -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].tunnelIpAddresses[0]' -o tsv)

prState=''
rtState=''
while [[ $prState != 'Succeeded' ]];
do
    prState=$(az network vhub show -g $rg -n hubwest --query 'provisioningState' -o tsv)
    echo "hubwest provisioningState="$prState
    sleep 5
done

while [[ $rtState != 'Provisioned' ]];
do
    rtState=$(az network vhub show -g $rg -n hubwest --query 'routingState' -o tsv)
    echo "hubwest routingState="$rtState
    sleep 5
done

prState=''
while [[ $prState != 'Succeeded' ]];
do
    prState=$(az network vnet-gateway show -g $rg -n branchWestGW --query provisioningState -o tsv)
    echo "branchWestGW provisioningState="$prState
    sleep 5
done

bgp2=$(az network vnet-gateway show -n branchWestGW -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]' -o tsv)
pip2=$(az network vnet-gateway show -n branchWestGW -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].tunnelIpAddresses[0]' -o tsv)
vwanbgp2=$(az network vpn-gateway show -n hubwesttvpn2349829 -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]' -o tsv)
vwanpip2=$(az network vpn-gateway show -n hubwesttvpn2349829 -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].tunnelIpAddresses[0]' -o tsv)

# create virtual wan vpn site
az network vpn-site create --ip-address $pip1 -n site-east-1 -g $rg --asn 65510 --bgp-peering-address $bgp1 -l $loc1 --virtual-wan vwanvpn --device-model 'Azure' --device-vendor 'Microsoft' --link-speed '50' --with-link true
az network vpn-site create --ip-address $pip2 -n site-west-1 -g $rg --asn 65509 --bgp-peering-address $bgp2 -l $loc2 --virtual-wan vwanvpn --device-model 'Azure' --device-vendor 'Microsoft' --link-speed '50' --with-link true

# create virtual wan vpn connection
az network vpn-gateway connection create --gateway-name hubeastvpn23094989 -n site-east-1-conn -g $rg --enable-bgp true --remote-vpn-site site-east-1 --internet-security --shared-key 'abc123'
az network vpn-gateway connection create --gateway-name hubwesttvpn2349829 -n site-east-2-conn -g $rg --enable-bgp true --remote-vpn-site site-west-1 --internet-security --shared-key 'abc123'

# create connection from vpn gw to local gateway and watch for connection succeeded
az network local-gateway create -g $rg -n site-east-LG --gateway-ip-address $vwanpip1 --asn 65515 --bgp-peering-address $vwanbgp1 -l $loc1
az network vpn-connection create -n brancheasttositeeast -g $rg -l $loc1 --vnet-gateway1 branchEastGW --local-gateway2 site-east-LG --enable-bgp --shared-key 'abc123'

az network local-gateway create -g $rg -n site-west-LG --gateway-ip-address $vwanpip2 --asn 65515 --bgp-peering-address $vwanbgp2 -l $loc2
az network vpn-connection create -n branchwesttositewest -g $rg -l $loc2 --vnet-gateway1 branchWestGW --local-gateway2 site-west-LG --enable-bgp --shared-key 'abc123'

# create a VM in each branch spoke
username="azureuser"
password="MyP@ssword123"
mypip=$(curl -4 ifconfig.io -s)
az vm create -n branchEastVM  -g $rg --image ubuntults --public-ip-sku Standard --size Standard_D2S_v3 -l $loc1 --subnet main --vnet-name branchEast --admin-username $username --admin-password $password
az network nsg rule update -g $rg --nsg-name 'branchEastVMNSG' -n 'default-allow-ssh' --source-address-prefixes $mypip
az vm create -n branchWestVM  -g $rg --image ubuntults --public-ip-sku Standard --size Standard_D2S_v3 -l $loc2 --subnet main --vnet-name branchWest --admin-username $username --admin-password $password
az network nsg rule update -g $rg --nsg-name 'branchWestVMNSG' -n 'default-allow-ssh' --source-address-prefixes $mypip

# create a VM in each connected spoke
az vm create -n spoke1VM  -g $rg --image ubuntults --public-ip-sku Standard --size Standard_D2S_v3 -l $loc1 --subnet main --vnet-name spoke1 --admin-username $username --admin-password $password
az network nsg rule update -g $rg --nsg-name 'spoke1VMNSG' -n 'default-allow-ssh' --source-address-prefixes $mypip
az vm create -n spoke2VM  -g $rg --image ubuntults --public-ip-sku Standard --size Standard_D2S_v3 -l $loc2 --subnet main --vnet-name spoke2 --admin-username $username --admin-password $password
az network nsg rule update -g $rg --nsg-name 'spoke2VMNSG' -n 'default-allow-ssh' --source-address-prefixes $mypip
