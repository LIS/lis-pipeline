#!/bin/bash

LATEST_IMAGES_PATH=""./latest_images.txt""
get_latest_image() {
    local publisher=$1
    local offer=$2
    local sku=$3
    lastest_image_version=$(az vm image list -l westus2 \
                            --publisher $publisher --offer $offer --query "[?sku=='$sku'].*" --all -o tsv | \
                            grep -i "$publisher:$offer:$sku:" | sort -r --version-sort | sed -n '1 p' | awk '{print $4}')
    if [[ $lastest_image_version != "" ]]; then
        echo "Last image for publisher ${publisher}, offer ${offer}, sku ${sku} and version ${lastest_image_version}"
        az vm image show --location westus2 --urn ${publisher}:${offer}:${sku}:${lastest_image_version}
        if [[ $? == 0 ]]; then
            echo "$publisher $offer $sku $lastest_image_version;" >> "${LATEST_IMAGES_PATH}"
        else
            echo "No image found for publisher ${publisher}, offer ${offer}, sku ${sku}"
        fi
    else
        echo "No image found for publisher ${publisher}, offer ${offer}, sku ${sku}"
    fi
}
get_latest_image $@
