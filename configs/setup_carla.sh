#!/usr/bin/env bash

# Download and install CARLA
# Source 1: Official CARLA website
# Source 2: Google Drive backup - https://drive.google.com/drive/folders/19CAHSRYdTnq4G9oFsyXbj7o2eVjDTYIj

mkdir -p carla
cd carla

# Try official download first, fall back to Google Drive
if wget https://tiny.carla.org/carla-0-9-10-1-linux -O CARLA_0.9.10.1.tar.gz; then
    echo "Downloaded CARLA from official source"
else
    echo "Official download failed, trying Google Drive..."
    pip install gdown -q
    gdown --folder https://drive.google.com/drive/folders/19CAHSRYdTnq4G9oFsyXbj7o2eVjDTYIj -O .
fi

if wget https://tiny.carla.org/additional-maps-0-9-10-1-linux -O AdditionalMaps_0.9.10.1.tar.gz; then
    echo "Downloaded AdditionalMaps from official source"
fi

# Extract and clean up
for f in *.tar.gz; do
    [ -f "$f" ] && tar -xf "$f" && rm "$f"
done

cd ..
