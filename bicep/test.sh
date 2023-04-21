#!/bin/bash

# Variables
prefix="Pink"
resourceGroupName="${prefix}RG"
deploymentName="deploymentScript"

# Get the URL of the productpage of the bookinfo sample application
bookInfoUrlExternal=$(az deployment group show \
	--name $deploymentName \
	--resource-group $resourceGroupName \
	--query properties.outputs.bookInfoUrlExternal.value \
	--output tsv)

if [[ -n $bookInfoUrlExternal ]]; then
	echo "[$bookInfoUrlExternal] URL of the productpage of the bookinfo sample application successfully retrieved"
else
	echo "Failed to get the URL of the productpage of the bookinfo sample application"
	exit -1
fi

#  Call the URL of the productpage of the bookinfo sample application
echo "Calling the URL of the productpage of the bookinfo sample application"
curl -s $bookInfoUrlExternal | grep -o "<title>.*</title>"