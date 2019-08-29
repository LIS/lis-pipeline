#!/bin/bash

LATEST_IMAGES_PATH=""./latest_images.txt""
get_latest_image() {
    local publisher=$1
    local sku=$2
    local offer=$3
    last_image=$(az vm image list --all --location "westus2" \
      --publisher "${publisher}" --sku "${sku}" --offer "${offer}" \
      | grep -v "SAP\|CI\|DAILY" | grep "urn" \
      | sort -r --version-sort | sed -n '1 p' | awk '{print $2}')
    last_image=${last_image//\"/}
    last_image=${last_image//:/ }
    last_image=${last_image//,/}
    echo "Last image for publisher ${publisher} and sku ${sku}: ${last_image}"
    echo "${last_image};" >> "${LATEST_IMAGES_PATH}"
}
get_latest_image $@

